-- Enforce the same annual department-budget gate for every single-department
-- proposal source. AI-imported proposals previously bypassed the commitment
-- trigger even when they had a complete proposal budget.

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
  -- Only the transition into committed reserves money. Realtime refreshes and
  -- subsequent edits cannot charge the same proposal twice.
  if new.status <> 'committed' or old.status = 'committed' then return new; end if;

  -- Inter-department funding is a separate fiscal workflow. This gate covers
  -- every proposal whose only participating organization is its owner.
  if exists (
    select 1
    from public.proposal_collaboration_orgs
    where draft_id = new.id and participation_role <> 'owner'
  ) then return new; end if;

  select revision.snapshot -> 'budget'
    into budget_json
  from public.proposal_collaboration_revisions revision
  where revision.id = new.current_revision_id and revision.draft_id = new.id;

  if budget_json is null or jsonb_typeof(budget_json) <> 'object' then
    raise exception 'Add a proposal budget before publishing this department-only plan' using errcode = '22023';
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
    raise exception 'No locked % department budget exists. Save this proposal as an unfunded draft.', year using errcode = '22023';
  end if;

  select coalesce(sum(amount), 0) into already_committed
  from public.budget_commitments
  where fiscal_budget_id = fiscal.id and status = 'active';
  if already_committed + total > fiscal.approved_amount then
    raise exception 'Insufficient department budget. Shortfall: %',
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
    jsonb_build_object('proposalDraftId', new.id, 'revisionId', new.current_revision_id)
  );

  return new;
end;
$$;

notify pgrst, 'reload schema';
