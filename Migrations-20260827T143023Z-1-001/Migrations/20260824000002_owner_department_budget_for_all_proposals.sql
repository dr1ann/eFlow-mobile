-- Every proposal is funded by its owning organization's annual budget in the
-- current fiscal phase. Participating and governance organizations do not
-- bypass the owner's funding gate. Existing committed proposals are backfilled
-- when they have a valid budget and enough remaining owner funds.

create or replace function public.commit_single_department_proposal_budget()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  budget_json jsonb;
  line jsonb;
  total numeric := 0;
  line_total numeric := 0;
  year int;
  fiscal public.department_fiscal_budgets;
  already_committed numeric := 0;
  commitment_id uuid;
begin
  if new.status <> 'committed' or old.status = 'committed' then return new; end if;

  select revision.snapshot -> 'budget'
    into budget_json
  from public.proposal_collaboration_revisions revision
  where revision.id = new.current_revision_id and revision.draft_id = new.id;

  if budget_json is null or jsonb_typeof(budget_json) <> 'object' then
    raise exception 'Add a proposal budget before publishing this plan' using errcode = '22023';
  end if;

  total := coalesce((budget_json ->> 'totalAmount')::numeric, 0);
  year := coalesce((budget_json ->> 'fiscalYear')::int, extract(year from now())::int);
  if total <= 0 then
    raise exception 'Set a proposal budget greater than zero before publishing' using errcode = '22023';
  end if;
  if jsonb_typeof(coalesce(budget_json -> 'lines', '[]'::jsonb)) <> 'array' then
    raise exception 'Proposal budget lines are invalid' using errcode = '22023';
  end if;

  for line in
    select value from jsonb_array_elements(coalesce(budget_json -> 'lines', '[]'::jsonb))
  loop
    if nullif(btrim(line ->> 'expenseClass'), '') is null
       or nullif(btrim(line ->> 'category'), '') is null
       or nullif(btrim(line ->> 'particular'), '') is null
       or nullif(btrim(line ->> 'fundSource'), '') is null then
      raise exception 'Every proposal budget line needs an expense class, category, particular, and fund source' using errcode = '22023';
    end if;
    if coalesce((line ->> 'amount')::numeric, -1) < 0 then
      raise exception 'Proposal budget line amounts cannot be negative' using errcode = '22023';
    end if;
    line_total := line_total + coalesce((line ->> 'amount')::numeric, 0);
  end loop;

  if abs(line_total - total) > 0.009 then
    raise exception 'Proposal budget total does not match its line items' using errcode = '22023';
  end if;

  select * into fiscal
  from public.department_fiscal_budgets
  where org_id = new.owner_org_id and fiscal_year = year and status = 'locked'
  for update;
  if not found then
    raise exception 'No locked % owner-department budget exists. Keep this proposal as an unfunded draft.', year using errcode = '22023';
  end if;

  select coalesce(sum(amount), 0) into already_committed
  from public.budget_commitments
  where fiscal_budget_id = fiscal.id and status = 'active';
  if already_committed + total > fiscal.approved_amount then
    raise exception 'Insufficient owner-department budget. Shortfall: %',
      to_char((already_committed + total) - fiscal.approved_amount, 'FM999G999G999G990D00') using errcode = '22023';
  end if;

  insert into public.budget_commitments(
    fiscal_budget_id,
    proposal_draft_id,
    proposal_revision_id,
    title,
    amount,
    created_by
  ) values (
    fiscal.id,
    new.id,
    new.current_revision_id,
    new.title,
    total,
    auth.uid()
  ) returning id into commitment_id;

  insert into public.budget_ledger_entries(
    fiscal_budget_id,
    org_id,
    commitment_id,
    entry_type,
    amount,
    description,
    actor_id,
    metadata
  ) values (
    fiscal.id,
    fiscal.org_id,
    commitment_id,
    'proposal_committed',
    total,
    'Budget reserved for published proposal: ' || new.title,
    auth.uid(),
    jsonb_build_object(
      'proposalDraftId', new.id,
      'revisionId', new.current_revision_id,
      'fundingOrganizationId', new.owner_org_id
    )
  );

  return new;
end;
$$;

-- Backfill already-published proposals that were skipped by the old
-- inter-department bypass. Oldest proposals are reserved first and the running
-- total is never allowed to exceed the locked annual appropriation.
with candidate_budgets as (
  select
    draft.id as draft_id,
    draft.current_revision_id as revision_id,
    draft.title,
    draft.created_by,
    draft.owner_org_id,
    coalesce(draft.committed_at, draft.created_at) as committed_at,
    revision.snapshot -> 'budget' as budget_json
  from public.proposal_collaboration_drafts draft
  join public.proposal_collaboration_revisions revision
    on revision.id = draft.current_revision_id
   and revision.draft_id = draft.id
  where draft.status = 'committed'
    and not exists (
      select 1 from public.budget_commitments commitment
      where commitment.proposal_draft_id = draft.id
    )
    and jsonb_typeof(revision.snapshot -> 'budget') = 'object'
), normalized as (
  select
    candidate.*,
    case
      when coalesce(candidate.budget_json ->> 'fiscalYear', '') ~ '^[0-9]{4}$'
        then (candidate.budget_json ->> 'fiscalYear')::int
      else extract(year from candidate.committed_at)::int
    end as fiscal_year,
    case
      when coalesce(candidate.budget_json ->> 'totalAmount', '') ~ '^[0-9]+([.][0-9]+)?$'
        then (candidate.budget_json ->> 'totalAmount')::numeric
      else 0
    end as amount,
    totals.line_total
  from candidate_budgets candidate
  cross join lateral (
    select coalesce(sum(
      case
        when coalesce(item ->> 'amount', '') ~ '^[0-9]+([.][0-9]+)?$'
          then (item ->> 'amount')::numeric
        else 0
      end
    ), 0) as line_total
    from jsonb_array_elements(
      case
        when jsonb_typeof(candidate.budget_json -> 'lines') = 'array'
          then candidate.budget_json -> 'lines'
        else '[]'::jsonb
      end
    ) item
  ) totals
), funded as (
  select
    normalized.*,
    fiscal.id as fiscal_budget_id,
    fiscal.approved_amount,
    coalesce(existing.amount, 0) as existing_commitments
  from normalized
  join public.department_fiscal_budgets fiscal
    on fiscal.org_id = normalized.owner_org_id
   and fiscal.fiscal_year = normalized.fiscal_year
   and fiscal.status = 'locked'
  left join lateral (
    select coalesce(sum(commitment.amount), 0) as amount
    from public.budget_commitments commitment
    where commitment.fiscal_budget_id = fiscal.id
      and commitment.status = 'active'
  ) existing on true
  where normalized.amount > 0
    and abs(normalized.line_total - normalized.amount) <= 0.009
), ranked as (
  select
    funded.*,
    sum(funded.amount) over (
      partition by funded.fiscal_budget_id
      order by funded.committed_at, funded.draft_id
    ) as backfill_running_total
  from funded
), inserted as (
  insert into public.budget_commitments(
    fiscal_budget_id,
    proposal_draft_id,
    proposal_revision_id,
    title,
    amount,
    created_by
  )
  select
    ranked.fiscal_budget_id,
    ranked.draft_id,
    ranked.revision_id,
    ranked.title,
    ranked.amount,
    ranked.created_by
  from ranked
  where ranked.existing_commitments + ranked.backfill_running_total <= ranked.approved_amount
  on conflict (proposal_draft_id) do nothing
  returning id, fiscal_budget_id, proposal_draft_id, proposal_revision_id, title, amount, created_by
)
insert into public.budget_ledger_entries(
  fiscal_budget_id,
  org_id,
  commitment_id,
  entry_type,
  amount,
  description,
  actor_id,
  metadata
)
select
  inserted.fiscal_budget_id,
  fiscal.org_id,
  inserted.id,
  'proposal_committed',
  inserted.amount,
  'Budget backfilled for previously published proposal: ' || inserted.title,
  inserted.created_by,
  jsonb_build_object(
    'proposalDraftId', inserted.proposal_draft_id,
    'revisionId', inserted.proposal_revision_id,
    'backfilled', true
  )
from inserted
join public.department_fiscal_budgets fiscal on fiscal.id = inserted.fiscal_budget_id;

notify pgrst, 'reload schema';
