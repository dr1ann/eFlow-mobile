-- Task-linked proposal funding and a staged, daily-capped petty-cash workflow.
-- Proposal publication, task allocations, releases, receipts, and settlement
-- remain inside the owning department's locked annual appropriation.

begin;

alter table public.notifications
  add column if not exists financial_record_id uuid,
  add column if not exists financial_record_type text;

alter table public.department_fiscal_budgets
  add column if not exists daily_petty_cash_release_limit numeric(16,2) not null default 30000 check (daily_petty_cash_release_limit > 0),
  add column if not exists per_receipt_limit numeric(16,2) not null default 5000 check (per_receipt_limit > 0),
  add column if not exists liquidation_due_days int not null default 5 check (liquidation_due_days between 1 and 90),
  add column if not exists allow_receipt_limit_override boolean not null default false;

update public.department_fiscal_budgets
set daily_petty_cash_release_limit = greatest(petty_cash_limit, 1),
    per_receipt_limit = greatest(petty_cash_request_limit, 1)
where daily_petty_cash_release_limit = 30000
  and per_receipt_limit = 5000;

alter table public.department_budget_lines
  add column if not exists quantity numeric(16,2) not null default 1 check (quantity >= 0),
  add column if not exists unit text not null default 'item',
  add column if not exists unit_cost numeric(16,2) not null default 0 check (unit_cost >= 0);

update public.department_budget_lines
set unit_cost = approved_amount
where unit_cost = 0 and approved_amount > 0;

create table if not exists public.work_budget_allocation_lines (
  id uuid primary key default gen_random_uuid(),
  allocation_id uuid not null references public.work_budget_allocations(id) on delete restrict,
  draft_task_key text,
  expense_class text not null,
  category text not null,
  particular text not null,
  quantity numeric(16,2) not null default 1 check (quantity >= 0),
  unit text not null default 'item',
  unit_cost numeric(16,2) not null default 0 check (unit_cost >= 0),
  amount numeric(16,2) not null check (amount >= 0),
  fund_source text not null default 'Department Budget',
  position int not null default 0,
  created_at timestamptz not null default now()
);

create index if not exists work_budget_allocation_lines_allocation_idx
  on public.work_budget_allocation_lines(allocation_id, position);

alter table public.petty_cash_requests
  add column if not exists task_leader_id uuid references public.profiles(id) on delete restrict,
  add column if not exists cash_recipient_id uuid references public.profiles(id) on delete restrict,
  add column if not exists leader_decided_by uuid references public.profiles(id) on delete restrict,
  add column if not exists leader_decision_reason text,
  add column if not exists leader_decided_at timestamptz,
  add column if not exists department_decision_reason text,
  add column if not exists scheduled_amount numeric(16,2) not null default 0 check (scheduled_amount >= 0),
  add column if not exists released_amount numeric(16,2) not null default 0 check (released_amount >= 0),
  add column if not exists liquidation_due_at timestamptz;

do $$
declare constraint_name text;
begin
  for constraint_name in
    select con.conname
    from pg_constraint con
    where con.conrelid = 'public.petty_cash_requests'::regclass
      and con.contype = 'c'
      and pg_get_constraintdef(con.oid) ilike '%status%'
  loop
    execute format('alter table public.petty_cash_requests drop constraint %I', constraint_name);
  end loop;
end;
$$;

alter table public.petty_cash_requests
  alter column status set default 'pending_leader_review',
  add constraint petty_cash_requests_status_check check (status in (
    'draft', 'pending', 'pending_leader_review', 'leader_changes_requested',
    'pending_department_approval', 'department_changes_requested', 'approved',
    'scheduled_for_release', 'partially_released', 'released', 'rejected', 'cancelled',
    'liquidation_draft', 'liquidation_submitted', 'pending_leader_liquidation_review',
    'pending_department_settlement', 'changes_requested', 'overdue_liquidation', 'settled'
  ));

create table if not exists public.petty_cash_releases (
  id uuid primary key default gen_random_uuid(),
  request_id uuid not null references public.petty_cash_requests(id) on delete restrict,
  org_id uuid not null references public.organizations(id) on delete restrict,
  scheduled_date date not null,
  amount numeric(16,2) not null check (amount > 0),
  status text not null default 'scheduled' check (status in ('scheduled', 'released', 'cancelled')),
  recipient_id uuid not null references public.profiles(id) on delete restrict,
  released_by uuid references public.profiles(id) on delete restrict,
  released_at timestamptz,
  created_by uuid not null references public.profiles(id) on delete restrict,
  created_at timestamptz not null default now()
);

create index if not exists petty_cash_releases_org_date_idx
  on public.petty_cash_releases(org_id, scheduled_date, status);
create index if not exists petty_cash_releases_request_idx
  on public.petty_cash_releases(request_id, scheduled_date);

alter table public.petty_cash_liquidations
  add column if not exists leader_decided_by uuid references public.profiles(id) on delete restrict,
  add column if not exists leader_decision_reason text,
  add column if not exists leader_decided_at timestamptz,
  add column if not exists department_decided_by uuid references public.profiles(id) on delete restrict,
  add column if not exists department_decision_reason text,
  add column if not exists department_decided_at timestamptz;

do $$
declare constraint_name text;
begin
  for constraint_name in
    select con.conname
    from pg_constraint con
    where con.conrelid = 'public.petty_cash_liquidations'::regclass
      and con.contype = 'c'
      and pg_get_constraintdef(con.oid) ilike '%status%'
  loop
    execute format('alter table public.petty_cash_liquidations drop constraint %I', constraint_name);
  end loop;
end;
$$;

alter table public.petty_cash_liquidations
  add constraint petty_cash_liquidations_status_check check (status in (
    'pending', 'pending_leader_review', 'pending_department_settlement', 'approved', 'changes_requested'
  ));

create or replace function public.schedule_petty_cash_releases(p_request_id uuid, p_actor uuid)
returns numeric
language plpgsql
security definer
set search_path = public
as $$
declare
  request public.petty_cash_requests;
  budget public.department_fiscal_budgets;
  schedule_day date;
  remaining numeric;
  used_on_day numeric;
  tranche numeric;
  scheduled_total numeric := 0;
begin
  select * into request from public.petty_cash_requests where id = p_request_id for update;
  if not found then raise exception 'Petty-cash request not found' using errcode = 'P0002'; end if;
  select * into budget from public.department_fiscal_budgets where id = request.fiscal_budget_id and status = 'locked' for update;
  if not found then raise exception 'The annual department budget is no longer open' using errcode = '22023'; end if;
  delete from public.petty_cash_releases where request_id = request.id and status = 'scheduled';
  schedule_day := greatest(current_date, coalesce(request.needed_by, current_date));
  remaining := coalesce(request.approved_amount, request.requested_amount);
  while remaining > 0 loop
    select coalesce(sum(amount), 0) into used_on_day
    from public.petty_cash_releases
    where org_id = request.org_id and scheduled_date = schedule_day and status in ('scheduled', 'released');
    tranche := least(remaining, greatest(0, budget.daily_petty_cash_release_limit - used_on_day));
    if tranche > 0 then
      insert into public.petty_cash_releases(request_id, org_id, scheduled_date, amount, recipient_id, created_by)
      values (request.id, request.org_id, schedule_day, tranche, coalesce(request.cash_recipient_id, request.requester_id), p_actor);
      scheduled_total := scheduled_total + tranche;
      remaining := remaining - tranche;
    end if;
    if remaining > 0 then schedule_day := schedule_day + 1; end if;
  end loop;
  update public.petty_cash_requests set scheduled_amount = scheduled_total,
    status = 'scheduled_for_release', updated_at = now() where id = request.id;
  return scheduled_total;
end;
$$;

create or replace function public.create_petty_cash_request(
  p_allocation_id uuid,
  p_amount numeric,
  p_purpose text,
  p_needed_by date
) returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  caller uuid := auth.uid();
  allocation public.work_budget_allocations;
  commitment public.budget_commitments;
  budget public.department_fiscal_budgets;
  task public.tasks;
  request_id uuid;
  task_leader uuid;
  request_status text;
  allocation_used numeric := 0;
begin
  select * into allocation from public.work_budget_allocations where id = p_allocation_id and status = 'approved';
  if not found then raise exception 'Choose an approved task or subtask budget allocation' using errcode = '22023'; end if;
  select * into commitment from public.budget_commitments where id = allocation.commitment_id and status = 'active';
  if not found then raise exception 'The proposal budget is no longer active' using errcode = '22023'; end if;
  select * into budget from public.department_fiscal_budgets where id = commitment.fiscal_budget_id and status = 'locked';
  if not found then raise exception 'The annual department budget is no longer open' using errcode = '22023'; end if;
  select * into task from public.tasks where id = allocation.task_id;
  if not found then raise exception 'The funded task no longer exists' using errcode = 'P0002'; end if;
  task_leader := coalesce(task.recommendation_lead_id, task.assigned_to);
  if task_leader is null then raise exception 'This task has no Team Leader for petty-cash routing' using errcode = '22023'; end if;
  if caller is null or not (
    caller = task_leader
    or (
      allocation.subtask_id is not null
      and exists (
        select 1 from public.subtasks subtask
        where subtask.id = allocation.subtask_id
          and coalesce(subtask.assigned_to_ids, '{}'::uuid[]) @> array[caller]
      )
    )
  ) then
    raise exception 'Only the Task Leader or an assigned subtask contributor can request against this allocation' using errcode = '42501';
  end if;
  if p_amount <= 0 then raise exception 'Requested amount must be greater than zero' using errcode = '22023'; end if;
  if nullif(btrim(p_purpose), '') is null then raise exception 'Explain what the petty cash will be used for' using errcode = '22023'; end if;
  select coalesce(sum(case when status = 'settled' then actual_spent else requested_amount end), 0) into allocation_used
  from public.petty_cash_requests where allocation_id = allocation.id
    and status not in ('rejected', 'cancelled', 'leader_changes_requested', 'department_changes_requested');
  if allocation_used + p_amount > allocation.amount then
    raise exception 'This work allocation does not have enough remaining funds' using errcode = '22023';
  end if;
  request_status := case when caller = task_leader then 'pending_department_approval' else 'pending_leader_review' end;
  insert into public.petty_cash_requests(
    fiscal_budget_id, commitment_id, allocation_id, org_id, task_id, subtask_id,
    requester_id, task_leader_id, cash_recipient_id, purpose, requested_amount, needed_by, status
  ) values (
    budget.id, commitment.id, allocation.id, budget.org_id, allocation.task_id, allocation.subtask_id,
    caller, task_leader, caller, btrim(p_purpose), p_amount, p_needed_by, request_status
  ) returning id into request_id;
  if request_status = 'pending_leader_review' then
    insert into public.notifications(user_id, type, title, message, task_id, task_title, actor_id, actor_name, financial_record_id, financial_record_type)
    select task_leader, 'petty_cash_leader_review', 'Petty cash needs your endorsement',
      coalesce(profile.full_name, 'A team member') || ' requested ' || to_char(p_amount, 'FM999G999G999G990D00') || ' for "' || task.title || '".',
      task.id, task.title, caller, coalesce(profile.full_name, ''), request_id, 'petty_cash_request' from public.profiles profile where profile.id = caller and task_leader <> caller;
  else
    insert into public.notifications(user_id, type, title, message, task_id, task_title, actor_id, actor_name, financial_record_id, financial_record_type)
    select approver_id, 'petty_cash_department_approval', 'Petty cash awaiting department approval',
      coalesce(profile.full_name, 'A Task Leader') || ' requested ' || to_char(p_amount, 'FM999G999G999G990D00') || ' for "' || task.title || '".',
      task.id, task.title, caller, coalesce(profile.full_name, ''), request_id, 'petty_cash_request'
    from public.organization_approver_ids(task.org_id) approver_id
    left join public.profiles profile on profile.id = caller
    where approver_id <> caller;
  end if;
  return request_id;
end;
$$;

create or replace function public.decide_petty_cash_leader_review(
  p_request_id uuid,
  p_approve boolean,
  p_reason text
) returns void
language plpgsql
security definer
set search_path = public
as $$
declare caller uuid := auth.uid(); request public.petty_cash_requests; task public.tasks;
begin
  select * into request from public.petty_cash_requests where id = p_request_id for update;
  if not found then raise exception 'Petty-cash request not found' using errcode = 'P0002'; end if;
  if request.status <> 'pending_leader_review' then raise exception 'This request is not awaiting Team Leader review' using errcode = '22023'; end if;
  if request.task_leader_id <> caller then raise exception 'Only the assigned Team Leader can endorse this request' using errcode = '42501'; end if;
  if request.requester_id = caller then raise exception 'You cannot review your own request' using errcode = '42501'; end if;
  if not p_approve and nullif(btrim(p_reason), '') is null then raise exception 'Explain what the employee must change' using errcode = '22023'; end if;
  update public.petty_cash_requests set
    status = case when p_approve then 'pending_department_approval' else 'leader_changes_requested' end,
    leader_decided_by = caller, leader_decision_reason = nullif(btrim(p_reason), ''), leader_decided_at = now(), updated_at = now()
  where id = request.id;
  select * into task from public.tasks where id = request.task_id;
  if p_approve then
    insert into public.notifications(user_id, type, title, message, task_id, task_title, actor_id, actor_name, financial_record_id, financial_record_type)
    select approver_id, 'petty_cash_department_approval', 'Endorsed petty cash needs approval',
      'The Team Leader endorsed ' || to_char(request.requested_amount, 'FM999G999G999G990D00') || ' for "' || task.title || '".',
      task.id, task.title, caller, coalesce(profile.full_name, ''), request.id, 'petty_cash_request'
    from public.organization_approver_ids(request.org_id) approver_id
    left join public.profiles profile on profile.id = caller
    where approver_id <> caller;
  else
    insert into public.notifications(user_id, type, title, message, task_id, task_title, actor_id, actor_name, reason, financial_record_id, financial_record_type)
    select request.requester_id, 'petty_cash_changes', 'Petty-cash request needs changes',
      'Your Team Leader returned the petty-cash request for correction.', task.id, task.title,
      caller, coalesce(full_name, ''), p_reason, request.id, 'petty_cash_request' from public.profiles where id = caller;
  end if;
end;
$$;

create or replace function public.decide_petty_cash_request(
  p_request_id uuid,
  p_approve boolean,
  p_reason text
) returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  caller uuid := auth.uid();
  request public.petty_cash_requests;
  budget public.department_fiscal_budgets;
  allocation public.work_budget_allocations;
  allocation_used numeric;
begin
  select * into request from public.petty_cash_requests where id = p_request_id for update;
  if not found then raise exception 'Petty-cash request not found' using errcode = 'P0002'; end if;
  if request.status <> 'pending_department_approval' then raise exception 'This request is not awaiting department approval' using errcode = '22023'; end if;
  if not public.is_department_budget_approver(request.org_id, caller) then raise exception 'Only the Head or Assistant Head can decide this request' using errcode = '42501'; end if;
  if caller = request.requester_id then raise exception 'You cannot approve your own request' using errcode = '42501'; end if;
  if caller = request.leader_decided_by then raise exception 'The Team Leader endorsement and department approval must be made by different people' using errcode = '42501'; end if;
  if not p_approve and nullif(btrim(p_reason), '') is null then raise exception 'A reason is required when declining' using errcode = '22023'; end if;
  if p_approve then
    select * into budget from public.department_fiscal_budgets where id = request.fiscal_budget_id and status = 'locked' for update;
    if not found then raise exception 'The annual department budget is no longer open' using errcode = '22023'; end if;
    select * into allocation from public.work_budget_allocations where id = request.allocation_id and status = 'approved' for update;
    if not found then raise exception 'The work allocation is no longer available' using errcode = '22023'; end if;
    select coalesce(sum(case when status = 'settled' then actual_spent else approved_amount end), 0) into allocation_used
    from public.petty_cash_requests where allocation_id = allocation.id and id <> request.id
      and status in ('approved','scheduled_for_release','partially_released','released','liquidation_submitted','pending_leader_liquidation_review','pending_department_settlement','changes_requested','overdue_liquidation','settled');
    if allocation_used + request.requested_amount > allocation.amount then raise exception 'The work allocation is no longer sufficient' using errcode = '22023'; end if;
  end if;
  update public.petty_cash_requests set
    status = case when p_approve then 'approved' else 'rejected' end,
    approved_amount = case when p_approve then requested_amount end,
    approved_by = caller, approval_reason = nullif(btrim(p_reason), ''),
    department_decision_reason = nullif(btrim(p_reason), ''), decided_at = now(), updated_at = now()
  where id = request.id;
  if p_approve then
    perform public.schedule_petty_cash_releases(request.id, caller);
    insert into public.budget_ledger_entries(fiscal_budget_id, org_id, commitment_id, allocation_id, petty_cash_request_id, entry_type, amount, description, actor_id)
    values (request.fiscal_budget_id, request.org_id, request.commitment_id, request.allocation_id, request.id,
      'petty_cash_reserved', request.requested_amount, 'Petty cash approved and scheduled under the daily release cap', caller);
  end if;
  insert into public.notifications(user_id, type, title, message, task_id, actor_id, actor_name, reason, financial_record_id, financial_record_type)
  select request.requester_id, 'petty_cash_decision', case when p_approve then 'Petty cash approved and scheduled' else 'Petty cash declined' end,
    case when p_approve then 'Your request was approved. Cash releases were scheduled under the department daily cap.' else 'Your petty-cash request was declined.' end,
    request.task_id, caller, coalesce(full_name, ''), coalesce(p_reason, ''), request.id, 'petty_cash_request' from public.profiles where id = caller;
end;
$$;

create or replace function public.mark_petty_cash_released(p_release_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare caller uuid := auth.uid(); release public.petty_cash_releases; request public.petty_cash_requests; released_total numeric;
begin
  select * into release from public.petty_cash_releases where id = p_release_id for update;
  if not found then raise exception 'Scheduled release not found' using errcode = 'P0002'; end if;
  select * into request from public.petty_cash_requests where id = release.request_id for update;
  if not public.is_department_budget_approver(request.org_id, caller) then raise exception 'Only the Head or Assistant Head can record a cash release' using errcode = '42501'; end if;
  if release.status <> 'scheduled' then raise exception 'This cash tranche has already been processed' using errcode = '22023'; end if;
  if release.scheduled_date > current_date then raise exception 'This tranche is scheduled for %', release.scheduled_date using errcode = '22023'; end if;
  update public.petty_cash_releases set status = 'released', released_by = caller, released_at = now() where id = release.id;
  select coalesce(sum(amount), 0) into released_total from public.petty_cash_releases where request_id = request.id and status = 'released';
  update public.petty_cash_requests set released_amount = released_total,
    status = case when released_total >= approved_amount then 'released' else 'partially_released' end,
    liquidation_due_at = case when released_total >= approved_amount then now() + (select liquidation_due_days from public.department_fiscal_budgets where id = request.fiscal_budget_id) * interval '1 day' else liquidation_due_at end,
    updated_at = now() where id = request.id;
  insert into public.budget_ledger_entries(fiscal_budget_id, org_id, commitment_id, allocation_id, petty_cash_request_id, entry_type, amount, description, actor_id)
  values (request.fiscal_budget_id, request.org_id, request.commitment_id, request.allocation_id, request.id,
    'petty_cash_released', release.amount, 'Scheduled petty-cash tranche released to recipient', caller);
  insert into public.notifications(user_id, type, title, message, task_id, actor_id, actor_name, financial_record_id, financial_record_type)
  select request.cash_recipient_id, 'petty_cash_released', 'Petty cash released',
    to_char(release.amount, 'FM999G999G999G990D00') || ' was recorded as released for your work request.',
    request.task_id, caller, coalesce(full_name, ''), release.id, 'petty_cash_release' from public.profiles where id = caller;
end;
$$;


create or replace function public.commit_single_department_proposal_budget()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  snapshot jsonb;
  budget_json jsonb;
  task_budget jsonb;
  task_json jsonb;
  line jsonb;
  task_total numeric;
  proposal_total numeric := 0;
  declared_total numeric := 0;
  quantity_value numeric;
  unit_cost_value numeric;
  amount_value numeric;
  year int;
  fiscal public.department_fiscal_budgets;
  already_committed numeric := 0;
  commitment_id uuid;
  allocation_id uuid;
  operational_task public.tasks;
  actor uuid;
begin
  if new.status <> 'committed' or old.status = 'committed' then return new; end if;
  actor := coalesce(auth.uid(), new.created_by);

  select revision.snapshot into snapshot
  from public.proposal_collaboration_revisions revision
  where revision.id = new.current_revision_id and revision.draft_id = new.id;
  budget_json := snapshot -> 'budget';
  if budget_json is null or jsonb_typeof(budget_json) <> 'object' then
    raise exception 'Complete the task funding schedule before publishing this proposal' using errcode = '22023';
  end if;
  if jsonb_typeof(coalesce(budget_json -> 'taskBudgets', '[]'::jsonb)) <> 'array'
     or jsonb_array_length(coalesce(budget_json -> 'taskBudgets', '[]'::jsonb)) = 0 then
    raise exception 'Every selected task must be marked funded or no cost before publishing' using errcode = '22023';
  end if;

  for task_json in
    select value from jsonb_array_elements(snapshot -> 'tasks')
    where coalesce((value ->> 'enabled')::boolean, true)
  loop
    select value into task_budget
    from jsonb_array_elements(budget_json -> 'taskBudgets')
    where value ->> 'taskKey' = task_json ->> 'key';
    if task_budget is null then
      raise exception 'Task "%" has no funding decision', task_json ->> 'title' using errcode = '22023';
    end if;
    if task_budget ->> 'decision' not in ('funded', 'no_cost') then
      raise exception 'Task "%" must be marked funded or no cost', task_json ->> 'title' using errcode = '22023';
    end if;
    if task_budget ->> 'decision' = 'no_cost' then
      continue;
    end if;
    if jsonb_typeof(coalesce(task_budget -> 'lines', '[]'::jsonb)) <> 'array'
       or jsonb_array_length(coalesce(task_budget -> 'lines', '[]'::jsonb)) = 0 then
      raise exception 'Task "%" needs at least one funded particular', task_json ->> 'title' using errcode = '22023';
    end if;
    task_total := 0;
    for line in select value from jsonb_array_elements(task_budget -> 'lines') loop
      if nullif(btrim(line ->> 'expenseClass'), '') is null or nullif(btrim(line ->> 'category'), '') is null
         or nullif(btrim(line ->> 'particular'), '') is null then
        raise exception 'Every task budget line needs an expense class, category, and particular' using errcode = '22023';
      end if;
      quantity_value := greatest(coalesce((line ->> 'quantity')::numeric, 1), 0);
      unit_cost_value := greatest(coalesce((line ->> 'unitCost')::numeric, (line ->> 'amount')::numeric, 0), 0);
      amount_value := case when quantity_value > 0 and unit_cost_value > 0 then quantity_value * unit_cost_value else greatest(coalesce((line ->> 'amount')::numeric, 0), 0) end;
      if amount_value <= 0 then raise exception 'Every funded particular must have an amount greater than zero' using errcode = '22023'; end if;
      task_total := task_total + amount_value;
    end loop;
    proposal_total := proposal_total + task_total;
  end loop;

  declared_total := coalesce((budget_json ->> 'totalAmount')::numeric, 0);
  if abs(declared_total - proposal_total) > 0.009 then
    raise exception 'Proposal funding total does not match its task budgets' using errcode = '22023';
  end if;
  year := coalesce((budget_json ->> 'fiscalYear')::int, extract(year from now())::int);
  select * into fiscal from public.department_fiscal_budgets
  where org_id = new.owner_org_id and fiscal_year = year and status = 'locked' for update;
  if not found then raise exception 'No locked % owner-department budget exists', year using errcode = '22023'; end if;
  select coalesce(sum(amount), 0) into already_committed
  from public.budget_commitments where fiscal_budget_id = fiscal.id and status = 'active';
  if already_committed + proposal_total > fiscal.approved_amount then
    raise exception 'Insufficient department budget. Shortfall: %',
      to_char((already_committed + proposal_total) - fiscal.approved_amount, 'FM999G999G999G990D00') using errcode = '22023';
  end if;

  insert into public.budget_commitments(
    fiscal_budget_id, proposal_draft_id, proposal_revision_id, title, amount, created_by
  ) values (fiscal.id, new.id, new.current_revision_id, new.title, proposal_total, actor)
  on conflict (proposal_draft_id) do update set
    proposal_revision_id = excluded.proposal_revision_id,
    title = excluded.title,
    amount = excluded.amount,
    updated_at = now()
  returning id into commitment_id;

  if proposal_total > 0 then
    insert into public.budget_ledger_entries(
      fiscal_budget_id, org_id, commitment_id, entry_type, amount, description, actor_id, metadata
    ) values (
      fiscal.id, fiscal.org_id, commitment_id, 'proposal_committed', proposal_total,
      'Budget reserved for published proposal: ' || new.title, actor,
      jsonb_build_object('proposalDraftId', new.id, 'revisionId', new.current_revision_id)
    );
  end if;

  for task_budget in
    select value from jsonb_array_elements(budget_json -> 'taskBudgets')
    where value ->> 'decision' = 'funded'
  loop
    select value into task_json from jsonb_array_elements(snapshot -> 'tasks')
    where value ->> 'key' = task_budget ->> 'taskKey'
      and coalesce((value ->> 'enabled')::boolean, true)
    limit 1;
    select * into operational_task
    from public.tasks task
    where task.source_collaboration_draft_id = new.id
      and task.source_collaboration_revision_id = new.current_revision_id
      and task.title = task_json ->> 'title'
      and coalesce(task.project_id, '') = coalesce(task_json ->> 'projectId', '')
      and coalesce(task.activity_id, '') = coalesce(task_json ->> 'activityId', '')
      and task.recommendation_lead_id = nullif(task_json ->> 'leadMemberId', '')::uuid
    order by task.created_at desc
    limit 1;
    if not found then
      raise exception 'Could not connect task budget for "%" to its operational task', task_budget ->> 'taskTitle' using errcode = '22023';
    end if;
    select coalesce(sum(
      case
        when greatest(coalesce((value ->> 'quantity')::numeric, 1), 0) > 0
         and greatest(coalesce((value ->> 'unitCost')::numeric, (value ->> 'amount')::numeric, 0), 0) > 0
        then greatest(coalesce((value ->> 'quantity')::numeric, 1), 0) * greatest(coalesce((value ->> 'unitCost')::numeric, (value ->> 'amount')::numeric, 0), 0)
        else greatest(coalesce((value ->> 'amount')::numeric, 0), 0)
      end
    ), 0) into task_total from jsonb_array_elements(task_budget -> 'lines');
    insert into public.work_budget_allocations(
      commitment_id, task_id, amount, status, reason, requested_by, decided_by, decision_reason, requested_at, decided_at
    ) values (
      commitment_id, operational_task.id, task_total, 'approved',
      'Automatically allocated from the approved proposal task budget', actor, actor,
      'Approved with proposal publication', now(), now()
    ) returning id into allocation_id;
    for line in select value from jsonb_array_elements(task_budget -> 'lines') loop
      quantity_value := greatest(coalesce((line ->> 'quantity')::numeric, 1), 0);
      unit_cost_value := greatest(coalesce((line ->> 'unitCost')::numeric, (line ->> 'amount')::numeric, 0), 0);
      amount_value := case when quantity_value > 0 and unit_cost_value > 0 then quantity_value * unit_cost_value else greatest(coalesce((line ->> 'amount')::numeric, 0), 0) end;
      insert into public.work_budget_allocation_lines(
        allocation_id, draft_task_key, expense_class, category, particular, quantity, unit, unit_cost,
        amount, fund_source, position
      ) values (
        allocation_id, task_budget ->> 'taskKey', btrim(line ->> 'expenseClass'), btrim(line ->> 'category'),
        btrim(line ->> 'particular'), quantity_value, coalesce(nullif(btrim(line ->> 'unit'), ''), 'item'), unit_cost_value,
        amount_value, coalesce(nullif(btrim(line ->> 'fundSource'), ''), 'Department Budget'), coalesce((line ->> 'position')::int, 0)
      );
    end loop;
    insert into public.budget_ledger_entries(
      fiscal_budget_id, org_id, commitment_id, allocation_id, entry_type, amount, description, actor_id, metadata
    ) values (
      fiscal.id, operational_task.org_id, commitment_id, allocation_id, 'allocation_approved', task_total,
      'Task allocation created from published proposal funding', actor,
      jsonb_build_object('taskId', operational_task.id, 'draftTaskKey', task_budget ->> 'taskKey')
    );
  end loop;
  return new;
end;
$$;


create or replace function public.save_department_fiscal_budget_v2(
  p_org_id uuid,
  p_fiscal_year int,
  p_daily_release_limit numeric,
  p_per_receipt_limit numeric,
  p_liquidation_due_days int,
  p_allow_receipt_limit_override boolean,
  p_underutilization_threshold numeric,
  p_notes text,
  p_lines jsonb
) returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  caller uuid := auth.uid();
  budget_id uuid;
  line jsonb;
  total numeric := 0;
  quantity_value numeric;
  unit_cost_value numeric;
  amount_value numeric;
begin
  if not public.is_department_budget_head(p_org_id, caller) then
    raise exception 'Only the assigned Department Head can create the annual budget' using errcode = '42501';
  end if;
  if p_fiscal_year < 2000 or p_fiscal_year > 2200 then raise exception 'Invalid fiscal year' using errcode = '22023'; end if;
  if p_daily_release_limit <= 0 then raise exception 'Daily release limit must be greater than zero' using errcode = '22023'; end if;
  if p_per_receipt_limit <= 0 then raise exception 'Per-receipt threshold must be greater than zero' using errcode = '22023'; end if;
  if p_liquidation_due_days < 1 or p_liquidation_due_days > 90 then raise exception 'Liquidation due days must be between 1 and 90' using errcode = '22023'; end if;
  if p_underutilization_threshold < 0 or p_underutilization_threshold > 100 then raise exception 'Utilization threshold must be from 0 to 100' using errcode = '22023'; end if;
  if jsonb_typeof(coalesce(p_lines, '[]'::jsonb)) <> 'array' or jsonb_array_length(coalesce(p_lines, '[]'::jsonb)) = 0 then
    raise exception 'Add at least one annual budget line' using errcode = '22023';
  end if;

  for line in select value from jsonb_array_elements(p_lines) loop
    if nullif(btrim(line ->> 'expenseClass'), '') is null or nullif(btrim(line ->> 'category'), '') is null
       or nullif(btrim(line ->> 'particular'), '') is null or nullif(btrim(line ->> 'fundSource'), '') is null then
      raise exception 'Every budget line needs an expense class, category, particular, and fund source' using errcode = '22023';
    end if;
    quantity_value := greatest(coalesce((line ->> 'quantity')::numeric, 1), 0);
    unit_cost_value := greatest(coalesce((line ->> 'unitCost')::numeric, (line ->> 'amount')::numeric, 0), 0);
    amount_value := case when quantity_value > 0 and unit_cost_value > 0 then quantity_value * unit_cost_value else greatest(coalesce((line ->> 'amount')::numeric, 0), 0) end;
    total := total + amount_value;
  end loop;

  select id into budget_id from public.department_fiscal_budgets
  where org_id = p_org_id and fiscal_year = p_fiscal_year for update;
  if budget_id is not null and exists (select 1 from public.department_fiscal_budgets where id = budget_id and status <> 'draft') then
    raise exception 'The annual budget is locked and cannot be edited' using errcode = '22023';
  end if;
  if budget_id is null then
    insert into public.department_fiscal_budgets (
      org_id, fiscal_year, approved_amount, petty_cash_limit, petty_cash_request_limit,
      daily_petty_cash_release_limit, per_receipt_limit, liquidation_due_days,
      allow_receipt_limit_override, underutilization_threshold, notes, created_by
    ) values (
      p_org_id, p_fiscal_year, total, p_daily_release_limit, p_per_receipt_limit,
      p_daily_release_limit, p_per_receipt_limit, p_liquidation_due_days,
      p_allow_receipt_limit_override, p_underutilization_threshold, nullif(btrim(p_notes), ''), caller
    ) returning id into budget_id;
  else
    update public.department_fiscal_budgets set
      approved_amount = total, petty_cash_limit = p_daily_release_limit, petty_cash_request_limit = p_per_receipt_limit,
      daily_petty_cash_release_limit = p_daily_release_limit, per_receipt_limit = p_per_receipt_limit,
      liquidation_due_days = p_liquidation_due_days, allow_receipt_limit_override = p_allow_receipt_limit_override,
      underutilization_threshold = p_underutilization_threshold, notes = nullif(btrim(p_notes), ''), updated_at = now()
    where id = budget_id;
    delete from public.department_budget_lines where fiscal_budget_id = budget_id;
  end if;

  for line in select value from jsonb_array_elements(p_lines) loop
    quantity_value := greatest(coalesce((line ->> 'quantity')::numeric, 1), 0);
    unit_cost_value := greatest(coalesce((line ->> 'unitCost')::numeric, (line ->> 'amount')::numeric, 0), 0);
    amount_value := case when quantity_value > 0 and unit_cost_value > 0 then quantity_value * unit_cost_value else greatest(coalesce((line ->> 'amount')::numeric, 0), 0) end;
    insert into public.department_budget_lines (
      fiscal_budget_id, expense_class, category, particular, quantity, unit, unit_cost,
      approved_amount, fund_source, position, created_by
    ) values (
      budget_id, btrim(line ->> 'expenseClass'), btrim(line ->> 'category'), btrim(line ->> 'particular'),
      quantity_value, coalesce(nullif(btrim(line ->> 'unit'), ''), 'item'), unit_cost_value,
      amount_value, btrim(line ->> 'fundSource'), coalesce((line ->> 'position')::int, 0), caller
    );
  end loop;
  insert into public.audit_events(actor_id, actor_name, entity_type, entity_id, action, after_data, org_id)
  select caller, coalesce(full_name, 'Department Head'), 'department_budget', budget_id::text,
    'department_budget.saved', jsonb_build_object('fiscalYear', p_fiscal_year, 'amount', total, 'dailyReleaseLimit', p_daily_release_limit, 'perReceiptLimit', p_per_receipt_limit), p_org_id
  from public.profiles where id = caller;
  return budget_id;
end;
$$;

create or replace function public.submit_petty_cash_liquidation(
  p_request_id uuid,
  p_declared_spent numeric,
  p_note text,
  p_receipts jsonb
) returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  caller uuid := auth.uid();
  request public.petty_cash_requests;
  budget public.department_fiscal_budgets;
  item jsonb;
  receipt_total numeric := 0;
  liquidation_id uuid;
  next_version int;
  liquidation_status text;
begin
  select * into request from public.petty_cash_requests where id = p_request_id for update;
  if not found then raise exception 'Petty-cash request not found' using errcode = 'P0002'; end if;
  if request.requester_id <> caller and request.cash_recipient_id <> caller then raise exception 'Only the cash recipient can submit this liquidation' using errcode = '42501'; end if;
  if request.status not in ('released', 'changes_requested', 'overdue_liquidation') then raise exception 'All scheduled cash must be released before liquidation' using errcode = '22023'; end if;
  if p_declared_spent < 0 or p_declared_spent > request.released_amount then raise exception 'Actual spending cannot exceed the amount released' using errcode = '22023'; end if;
  if nullif(btrim(p_note), '') is null then raise exception 'Add a liquidation note' using errcode = '22023'; end if;
  if jsonb_typeof(coalesce(p_receipts, '[]'::jsonb)) <> 'array' or jsonb_array_length(coalesce(p_receipts, '[]'::jsonb)) = 0 then raise exception 'Attach at least one receipt' using errcode = '22023'; end if;
  select * into budget from public.department_fiscal_budgets where id = request.fiscal_budget_id;
  for item in select value from jsonb_array_elements(p_receipts) loop
    if nullif(btrim(item ->> 'vendor'), '') is null or nullif(btrim(item ->> 'description'), '') is null
       or nullif(btrim(item ->> 'filePath'), '') is null or nullif(item ->> 'receiptDate', '') is null then
      raise exception 'Every receipt needs vendor, date, description, amount, and attachment' using errcode = '22023';
    end if;
    if coalesce((item ->> 'amount')::numeric, 0) > budget.per_receipt_limit then
      if not budget.allow_receipt_limit_override then
        raise exception 'Receipt exceeds the configured per-receipt threshold of %', to_char(budget.per_receipt_limit, 'FM999G999G999G990D00') using errcode = '22023';
      end if;
      if nullif(btrim(item ->> 'overrideReason'), '') is null then
        raise exception 'Explain every receipt above the configured threshold' using errcode = '22023';
      end if;
    end if;
    receipt_total := receipt_total + coalesce((item ->> 'amount')::numeric, 0);
  end loop;
  if abs(receipt_total - p_declared_spent) > 0.009 then raise exception 'Receipt amounts must equal the declared amount spent' using errcode = '22023'; end if;
  select coalesce(max(version), 0) + 1 into next_version from public.petty_cash_liquidations where request_id = request.id;
  liquidation_status := case when request.task_leader_id = caller then 'pending_department_settlement' else 'pending_leader_review' end;
  insert into public.petty_cash_liquidations(request_id, version, declared_spent, returned_amount, note, status, submitted_by)
  values (request.id, next_version, p_declared_spent, request.released_amount - p_declared_spent, btrim(p_note), liquidation_status, caller)
  returning id into liquidation_id;
  for item in select value from jsonb_array_elements(p_receipts) loop
    insert into public.petty_cash_receipts(
      liquidation_id, vendor, receipt_number, receipt_date, description, amount,
      file_name, file_path, mime_type, file_size, override_reason, created_by
    ) values (
      liquidation_id, btrim(item ->> 'vendor'), nullif(btrim(item ->> 'receiptNumber'), ''),
      (item ->> 'receiptDate')::date, btrim(item ->> 'description'), (item ->> 'amount')::numeric,
      item ->> 'fileName', item ->> 'filePath', coalesce(nullif(item ->> 'mimeType', ''), 'application/octet-stream'),
      coalesce((item ->> 'fileSize')::bigint, 0), nullif(btrim(item ->> 'overrideReason'), ''), caller
    );
  end loop;
  update public.petty_cash_requests set status = case when liquidation_status = 'pending_leader_review' then 'pending_leader_liquidation_review' else 'pending_department_settlement' end, updated_at = now() where id = request.id;
  if liquidation_status = 'pending_leader_review' then
    insert into public.notifications(user_id, type, title, message, task_id, actor_id, actor_name, financial_record_id, financial_record_type)
    select request.task_leader_id, 'petty_cash_liquidation_leader_review', 'Expense liquidation needs your review',
      coalesce(profile.full_name, 'A team member') || ' submitted receipts totaling ' || to_char(p_declared_spent, 'FM999G999G999G990D00') || '.',
      request.task_id, caller, coalesce(profile.full_name, ''), liquidation_id, 'petty_cash_liquidation' from public.profiles profile where profile.id = caller;
  else
    insert into public.notifications(user_id, type, title, message, task_id, actor_id, actor_name, financial_record_id, financial_record_type)
    select approver_id, 'petty_cash_liquidation_department_review', 'Expense liquidation ready for settlement',
      coalesce(profile.full_name, 'A Task Leader') || ' submitted receipts totaling ' || to_char(p_declared_spent, 'FM999G999G999G990D00') || '.',
      request.task_id, caller, coalesce(profile.full_name, ''), liquidation_id, 'petty_cash_liquidation'
    from public.organization_approver_ids(request.org_id) approver_id left join public.profiles profile on profile.id = caller
    where approver_id <> caller;
  end if;
  return liquidation_id;
end;
$$;

create or replace function public.decide_petty_cash_liquidation_leader_review(
  p_liquidation_id uuid,
  p_approve boolean,
  p_reason text
) returns void
language plpgsql
security definer
set search_path = public
as $$
declare caller uuid := auth.uid(); liquidation public.petty_cash_liquidations; request public.petty_cash_requests;
begin
  select * into liquidation from public.petty_cash_liquidations where id = p_liquidation_id for update;
  if not found then raise exception 'Liquidation not found' using errcode = 'P0002'; end if;
  select * into request from public.petty_cash_requests where id = liquidation.request_id for update;
  if liquidation.status <> 'pending_leader_review' or request.status <> 'pending_leader_liquidation_review' then raise exception 'This liquidation is not awaiting Team Leader review' using errcode = '22023'; end if;
  if request.task_leader_id <> caller then raise exception 'Only the assigned Team Leader can review this liquidation' using errcode = '42501'; end if;
  if request.cash_recipient_id = caller then raise exception 'You cannot review your own liquidation' using errcode = '42501'; end if;
  if not p_approve and nullif(btrim(p_reason), '') is null then raise exception 'Explain what must be corrected' using errcode = '22023'; end if;
  update public.petty_cash_liquidations set status = case when p_approve then 'pending_department_settlement' else 'changes_requested' end,
    leader_decided_by = caller, leader_decision_reason = nullif(btrim(p_reason), ''), leader_decided_at = now()
  where id = liquidation.id;
  update public.petty_cash_requests set status = case when p_approve then 'pending_department_settlement' else 'changes_requested' end, updated_at = now() where id = request.id;
  if p_approve then
    insert into public.notifications(user_id, type, title, message, task_id, actor_id, actor_name, financial_record_id, financial_record_type)
    select approver_id, 'petty_cash_liquidation_department_review', 'Endorsed liquidation ready for settlement',
      'The Team Leader endorsed receipts totaling ' || to_char(liquidation.declared_spent, 'FM999G999G999G990D00') || '.',
      request.task_id, caller, coalesce(profile.full_name, ''), liquidation.id, 'petty_cash_liquidation'
    from public.organization_approver_ids(request.org_id) approver_id left join public.profiles profile on profile.id = caller
    where approver_id <> caller;
  else
    insert into public.notifications(user_id, type, title, message, task_id, actor_id, actor_name, reason, financial_record_id, financial_record_type)
    select request.cash_recipient_id, 'petty_cash_liquidation_changes', 'Expense liquidation needs changes',
      'Your Team Leader returned the liquidation for correction.', request.task_id, caller, coalesce(full_name, ''), p_reason, liquidation.id, 'petty_cash_liquidation'
    from public.profiles where id = caller;
  end if;
end;
$$;

create or replace function public.decide_petty_cash_liquidation(
  p_liquidation_id uuid,
  p_approve boolean,
  p_reason text
) returns void
language plpgsql
security definer
set search_path = public
as $$
declare caller uuid := auth.uid(); liquidation public.petty_cash_liquidations; request public.petty_cash_requests;
begin
  select * into liquidation from public.petty_cash_liquidations where id = p_liquidation_id for update;
  if not found then raise exception 'Liquidation not found' using errcode = 'P0002'; end if;
  select * into request from public.petty_cash_requests where id = liquidation.request_id for update;
  if not public.is_department_budget_approver(request.org_id, caller) then raise exception 'Only the Head or Assistant Head can settle this liquidation' using errcode = '42501'; end if;
  if caller in (request.cash_recipient_id, request.requester_id) then raise exception 'You cannot settle your own liquidation' using errcode = '42501'; end if;
  if caller = liquidation.leader_decided_by then raise exception 'Leader review and department settlement must be performed by different people' using errcode = '42501'; end if;
  if liquidation.status <> 'pending_department_settlement' or request.status <> 'pending_department_settlement' then raise exception 'This liquidation is not awaiting department settlement' using errcode = '22023'; end if;
  if not p_approve and nullif(btrim(p_reason), '') is null then raise exception 'Explain what must be corrected' using errcode = '22023'; end if;
  update public.petty_cash_liquidations set status = case when p_approve then 'approved' else 'changes_requested' end,
    decided_by = caller, decision_reason = nullif(btrim(p_reason), ''), decided_at = now(),
    department_decided_by = caller, department_decision_reason = nullif(btrim(p_reason), ''), department_decided_at = now()
  where id = liquidation.id;
  if p_approve then
    update public.petty_cash_requests set status = 'settled', actual_spent = liquidation.declared_spent,
      returned_amount = liquidation.returned_amount, settled_by = caller, settled_at = now(), updated_at = now()
    where id = request.id;
    insert into public.budget_ledger_entries(fiscal_budget_id, org_id, commitment_id, allocation_id, petty_cash_request_id, entry_type, amount, description, actor_id)
    values (request.fiscal_budget_id, request.org_id, request.commitment_id, request.allocation_id, request.id,
      'expense_posted', liquidation.declared_spent, 'Verified receipts posted as actual task spending', caller);
    if liquidation.returned_amount > 0 then
      insert into public.budget_ledger_entries(fiscal_budget_id, org_id, commitment_id, allocation_id, petty_cash_request_id, entry_type, amount, description, actor_id)
      values (request.fiscal_budget_id, request.org_id, request.commitment_id, request.allocation_id, request.id,
        'cash_returned', liquidation.returned_amount, 'Unused released cash returned to the task allocation', caller);
    end if;
  else
    update public.petty_cash_requests set status = 'changes_requested', updated_at = now() where id = request.id;
  end if;
  insert into public.notifications(user_id, type, title, message, task_id, actor_id, actor_name, reason, financial_record_id, financial_record_type)
  select request.cash_recipient_id, 'petty_cash_liquidation_decision', case when p_approve then 'Expense liquidation settled' else 'Liquidation changes requested' end,
    case when p_approve then 'Your receipts were verified and actual spending was posted to the task budget.' else 'Your liquidation needs corrections before settlement.' end,
    request.task_id, caller, coalesce(full_name, ''), coalesce(p_reason, ''), liquidation.id, 'petty_cash_liquidation' from public.profiles where id = caller;
end;
$$;

create or replace function public.department_budget_summary(p_org_id uuid, p_fiscal_year int)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  budget public.department_fiscal_budgets;
  committed numeric := 0;
  spent numeric := 0;
  petty_reserved numeric := 0;
  released_today numeric := 0;
  scheduled_today numeric := 0;
begin
  if auth.uid() is null or not public.can_view_department_budget(p_org_id, auth.uid()) then raise exception 'Budget access denied' using errcode = '42501'; end if;
  select * into budget from public.department_fiscal_budgets where org_id = p_org_id and fiscal_year = p_fiscal_year;
  if not found then return null; end if;
  select coalesce(sum(amount), 0) into committed from public.budget_commitments where fiscal_budget_id = budget.id and status = 'active';
  select coalesce(sum(actual_spent), 0) into spent from public.petty_cash_requests where fiscal_budget_id = budget.id and status = 'settled';
  select coalesce(sum(case when status = 'settled' then 0 else greatest(coalesce(approved_amount, 0) - coalesce(actual_spent, 0) - coalesce(returned_amount, 0), 0) end), 0)
  into petty_reserved from public.petty_cash_requests where fiscal_budget_id = budget.id
    and status in ('approved','scheduled_for_release','partially_released','released','liquidation_submitted','pending_leader_liquidation_review','pending_department_settlement','changes_requested','overdue_liquidation');
  select coalesce(sum(amount), 0) into released_today from public.petty_cash_releases where org_id = p_org_id and scheduled_date = current_date and status = 'released';
  select coalesce(sum(amount), 0) into scheduled_today from public.petty_cash_releases where org_id = p_org_id and scheduled_date = current_date and status = 'scheduled';
  return jsonb_build_object(
    'id', budget.id, 'orgId', budget.org_id, 'fiscalYear', budget.fiscal_year, 'status', budget.status,
    'approvedAmount', budget.approved_amount, 'committedAmount', committed, 'spentAmount', spent,
    'availableAmount', greatest(0, budget.approved_amount - committed), 'commitmentRemaining', greatest(0, committed - spent),
    'dailyPettyCashReleaseLimit', budget.daily_petty_cash_release_limit, 'perReceiptLimit', budget.per_receipt_limit,
    'liquidationDueDays', budget.liquidation_due_days, 'allowReceiptLimitOverride', budget.allow_receipt_limit_override,
    'releasedToday', released_today, 'scheduledToday', scheduled_today,
    'dailyReleaseRemaining', greatest(0, budget.daily_petty_cash_release_limit - released_today - scheduled_today),
    'pettyCashLimit', budget.daily_petty_cash_release_limit, 'pettyCashRequestLimit', budget.per_receipt_limit,
    'pettyCashReserved', petty_reserved, 'pettyCashSpent', spent,
    'pettyCashAvailable', greatest(0, budget.daily_petty_cash_release_limit - released_today - scheduled_today),
    'underutilizationThreshold', budget.underutilization_threshold, 'notes', budget.notes,
    'lockedAt', budget.locked_at, 'updatedAt', budget.updated_at
  );
end;
$$;

alter table public.work_budget_allocation_lines enable row level security;
alter table public.petty_cash_releases enable row level security;

drop policy if exists work_budget_allocation_lines_read on public.work_budget_allocation_lines;
create policy work_budget_allocation_lines_read on public.work_budget_allocation_lines for select to authenticated
using (exists (
  select 1 from public.work_budget_allocations allocation
  where allocation.id = allocation_id and public.can_see_task(allocation.task_id, auth.uid())
));

drop policy if exists petty_cash_requests_read on public.petty_cash_requests;
create policy petty_cash_requests_read on public.petty_cash_requests for select to authenticated
using (
  requester_id = auth.uid() or cash_recipient_id = auth.uid() or task_leader_id = auth.uid()
  or public.is_department_budget_approver(org_id, auth.uid())
);

drop policy if exists petty_cash_liquidations_read on public.petty_cash_liquidations;
create policy petty_cash_liquidations_read on public.petty_cash_liquidations for select to authenticated
using (exists (
  select 1 from public.petty_cash_requests request
  where request.id = request_id and (
    request.requester_id = auth.uid() or request.cash_recipient_id = auth.uid() or request.task_leader_id = auth.uid()
    or public.is_department_budget_approver(request.org_id, auth.uid())
  )
));

drop policy if exists petty_cash_receipts_read on public.petty_cash_receipts;
create policy petty_cash_receipts_read on public.petty_cash_receipts for select to authenticated
using (exists (
  select 1 from public.petty_cash_liquidations liquidation
  join public.petty_cash_requests request on request.id = liquidation.request_id
  where liquidation.id = liquidation_id and (
    request.requester_id = auth.uid() or request.cash_recipient_id = auth.uid() or request.task_leader_id = auth.uid()
    or public.is_department_budget_approver(request.org_id, auth.uid())
  )
));

drop policy if exists petty_cash_releases_read on public.petty_cash_releases;
create policy petty_cash_releases_read on public.petty_cash_releases for select to authenticated
using (recipient_id = auth.uid() or exists (
  select 1 from public.petty_cash_requests request
  where request.id = request_id and (
    request.requester_id = auth.uid() or request.task_leader_id = auth.uid()
    or public.is_department_budget_approver(request.org_id, auth.uid())
  )
));

revoke all on public.work_budget_allocation_lines, public.petty_cash_releases from anon;
grant select on public.work_budget_allocation_lines, public.petty_cash_releases to authenticated;
grant execute on function public.save_department_fiscal_budget_v2(uuid,int,numeric,numeric,int,boolean,numeric,text,jsonb) to authenticated;
grant execute on function public.create_petty_cash_request(uuid,numeric,text,date) to authenticated;
grant execute on function public.decide_petty_cash_leader_review(uuid,boolean,text) to authenticated;
grant execute on function public.decide_petty_cash_request(uuid,boolean,text) to authenticated;
grant execute on function public.mark_petty_cash_released(uuid) to authenticated;
grant execute on function public.submit_petty_cash_liquidation(uuid,numeric,text,jsonb) to authenticated;
grant execute on function public.decide_petty_cash_liquidation_leader_review(uuid,boolean,text) to authenticated;
grant execute on function public.decide_petty_cash_liquidation(uuid,boolean,text) to authenticated;
grant execute on function public.department_budget_summary(uuid,int) to authenticated;

notify pgrst, 'reload schema';

commit;
