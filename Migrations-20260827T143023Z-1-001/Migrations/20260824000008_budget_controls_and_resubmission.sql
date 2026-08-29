-- Completes the department-only fiscal workflow with audited appropriation
-- adjustments, source-line subtask allocations, request resubmission, release
-- acknowledgement, overdue maintenance, and financial completion guards.

begin;

alter table public.work_budget_allocations
  add column if not exists parent_allocation_line_id uuid references public.work_budget_allocation_lines(id) on delete restrict;

alter table public.petty_cash_releases
  add column if not exists acknowledged_by uuid references public.profiles(id) on delete restrict,
  add column if not exists acknowledged_at timestamptz;

alter table public.petty_cash_receipts
  add column if not exists override_reason text;

create table if not exists public.department_budget_adjustments (
  id uuid primary key default gen_random_uuid(),
  fiscal_budget_id uuid not null references public.department_fiscal_budgets(id) on delete restrict,
  previous_amount numeric(16,2) not null check (previous_amount >= 0),
  adjusted_amount numeric(16,2) not null check (adjusted_amount >= 0),
  reason text not null,
  support_file_path text,
  created_by uuid not null references public.profiles(id) on delete restrict,
  created_at timestamptz not null default now()
);

create index if not exists department_budget_adjustments_budget_idx
  on public.department_budget_adjustments(fiscal_budget_id, created_at desc);

do $$
declare constraint_name text;
begin
  for constraint_name in
    select con.conname from pg_constraint con
    where con.conrelid = 'public.budget_ledger_entries'::regclass
      and con.contype = 'c'
      and pg_get_constraintdef(con.oid) ilike '%entry_type%'
  loop
    execute format('alter table public.budget_ledger_entries drop constraint %I', constraint_name);
  end loop;
end;
$$;

alter table public.budget_ledger_entries
  add constraint budget_ledger_entries_entry_type_check check (entry_type in (
    'budget_locked', 'budget_adjusted', 'budget_closed', 'proposal_committed',
    'proposal_released', 'allocation_approved', 'petty_cash_reserved',
    'petty_cash_released', 'expense_posted', 'cash_returned'
  ));

create or replace function public.guard_work_budget_allocation_caps()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  parent_allocation public.work_budget_allocations;
  parent_line public.work_budget_allocation_lines;
  allocated numeric := 0;
begin
  if new.subtask_id is null or new.status not in ('pending', 'approved') then return new; end if;
  select * into parent_allocation from public.work_budget_allocations
  where commitment_id = new.commitment_id and task_id = new.task_id
    and subtask_id is null and status = 'approved' for update;
  if not found then raise exception 'The task has no approved proposal allocation' using errcode = '22023'; end if;
  select coalesce(sum(amount), 0) into allocated from public.work_budget_allocations
  where commitment_id = new.commitment_id and task_id = new.task_id and subtask_id is not null
    and status in ('pending', 'approved') and id <> new.id;
  if allocated + new.amount > parent_allocation.amount then
    raise exception 'The task does not have enough unallocated funding' using errcode = '22023';
  end if;
  if new.parent_allocation_line_id is not null then
    select * into parent_line from public.work_budget_allocation_lines
    where id = new.parent_allocation_line_id and allocation_id = parent_allocation.id;
    if not found then raise exception 'Choose a budget particular from this task allocation' using errcode = '22023'; end if;
    select coalesce(sum(amount), 0) into allocated from public.work_budget_allocations
    where parent_allocation_line_id = parent_line.id and status in ('pending', 'approved') and id <> new.id;
    if allocated + new.amount > parent_line.amount then
      raise exception 'This budget particular does not have enough unallocated funding' using errcode = '22023';
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists work_budget_allocation_caps_guard on public.work_budget_allocations;
create trigger work_budget_allocation_caps_guard
before insert or update of amount, status, parent_allocation_line_id on public.work_budget_allocations
for each row execute function public.guard_work_budget_allocation_caps();

create or replace function public.create_subtask_budget_allocation(
  p_task_id uuid,
  p_subtask_id uuid,
  p_parent_allocation_line_id uuid,
  p_amount numeric,
  p_reason text
) returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  caller uuid := auth.uid();
  task public.tasks;
  parent_allocation public.work_budget_allocations;
  created_allocation_id uuid;
  initial_status text;
begin
  if caller is null then raise exception 'Not authenticated' using errcode = '42501'; end if;
  if p_amount <= 0 or nullif(btrim(p_reason), '') is null then raise exception 'Enter a positive amount and purpose' using errcode = '22023'; end if;
  select * into task from public.tasks where id = p_task_id;
  if not found then raise exception 'Task not found' using errcode = 'P0002'; end if;
  if not exists (select 1 from public.subtasks where id = p_subtask_id and task_id = task.id) then
    raise exception 'Subtask does not belong to this task' using errcode = '22023';
  end if;
  if caller is distinct from coalesce(task.recommendation_lead_id, task.assigned_to) then
    raise exception 'Only the Task Leader can distribute task funding to a subtask' using errcode = '42501';
  end if;
  select * into parent_allocation from public.work_budget_allocations
  where task_id = task.id and subtask_id is null and status = 'approved' for update;
  if not found then raise exception 'The task has no approved proposal allocation' using errcode = '22023'; end if;
  initial_status := 'pending';
  insert into public.work_budget_allocations(
    commitment_id, task_id, subtask_id, parent_allocation_line_id, amount,
    status, reason, requested_by, decided_by, decision_reason, requested_at, decided_at
  ) values (
    parent_allocation.commitment_id, task.id, p_subtask_id, p_parent_allocation_line_id,
    p_amount, initial_status, btrim(p_reason), caller,
    case when initial_status = 'approved' then caller end,
    case when initial_status = 'approved' then 'Allocated by department approver' end,
    now(), case when initial_status = 'approved' then now() end
  ) returning id into created_allocation_id;
  if p_parent_allocation_line_id is not null then
    insert into public.work_budget_allocation_lines(
      allocation_id, draft_task_key, expense_class, category, particular,
      quantity, unit, unit_cost, amount, fund_source, position
    )
    select created_allocation_id, draft_task_key, expense_class, category, particular,
      1, 'allocation', p_amount, p_amount, fund_source, 0
    from public.work_budget_allocation_lines where id = p_parent_allocation_line_id;
  end if;
  insert into public.notifications(user_id, type, title, message, task_id, task_title, actor_id, actor_name, financial_record_id, financial_record_type)
  select distinct approver_id, 'budget_approval', 'Subtask funding needs approval',
    coalesce(profile.full_name, 'A Task Leader') || ' proposed ' || to_char(p_amount, 'FM999G999G999G990D00') || ' for a subtask in "' || task.title || '".',
    task.id, task.title, caller, coalesce(profile.full_name, ''), created_allocation_id, 'work_budget_allocation'
  from public.organization_approver_ids(task.org_id) approver_id
  left join public.profiles profile on profile.id = caller where approver_id <> caller;
  return created_allocation_id;
end;
$$;

create or replace function public.resubmit_petty_cash_request(
  p_request_id uuid,
  p_amount numeric,
  p_purpose text,
  p_needed_by date
) returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  caller uuid := auth.uid();
  request public.petty_cash_requests;
  allocation public.work_budget_allocations;
  used numeric := 0;
  next_status text;
begin
  select * into request from public.petty_cash_requests where id = p_request_id for update;
  if not found then raise exception 'Petty-cash request not found' using errcode = 'P0002'; end if;
  if request.requester_id <> caller then raise exception 'Only the requester can correct this request' using errcode = '42501'; end if;
  if request.status not in ('leader_changes_requested', 'department_changes_requested') then
    raise exception 'This request is not awaiting corrections' using errcode = '22023';
  end if;
  if p_amount <= 0 or nullif(btrim(p_purpose), '') is null then raise exception 'Enter a positive amount and purpose' using errcode = '22023'; end if;
  select * into allocation from public.work_budget_allocations where id = request.allocation_id and status = 'approved' for update;
  if not found then raise exception 'The work allocation is no longer available' using errcode = '22023'; end if;
  select coalesce(sum(case when status = 'settled' then actual_spent else coalesce(approved_amount, requested_amount) end), 0)
  into used from public.petty_cash_requests
  where allocation_id = allocation.id and id <> request.id
    and status not in ('draft', 'rejected', 'cancelled', 'leader_changes_requested', 'department_changes_requested');
  if used + p_amount > allocation.amount then raise exception 'The work allocation does not have enough remaining funds' using errcode = '22023'; end if;
  next_status := case when request.requester_id = request.task_leader_id then 'pending_department_approval' else 'pending_leader_review' end;
  update public.petty_cash_requests set requested_amount = p_amount, purpose = btrim(p_purpose),
    needed_by = p_needed_by, status = next_status, approved_amount = null, approved_by = null,
    approval_reason = null, decided_at = null, leader_decided_by = null,
    leader_decision_reason = null, leader_decided_at = null, department_decision_reason = null,
    scheduled_amount = 0, released_amount = 0, updated_at = now()
  where id = request.id;
  insert into public.notifications(user_id, type, title, message, task_id, actor_id, actor_name, financial_record_id, financial_record_type)
  select distinct reviewer_id, 'petty_cash_resubmitted', 'Corrected petty-cash request ready',
    coalesce(profile.full_name, 'A team member') || ' resubmitted a corrected petty-cash request.',
    request.task_id, caller, coalesce(profile.full_name, ''), request.id, 'petty_cash_request'
  from (
    select request.task_leader_id reviewer_id where next_status = 'pending_leader_review'
    union
    select approver_id from public.organization_approver_ids(request.org_id)
    where next_status = 'pending_department_approval'
  ) reviewers
  left join public.profiles profile on profile.id = caller
  where reviewer_id is not null and reviewer_id <> caller;
end;
$$;

create or replace function public.acknowledge_petty_cash_release(p_release_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare caller uuid := auth.uid(); release public.petty_cash_releases;
begin
  select * into release from public.petty_cash_releases where id = p_release_id for update;
  if not found then raise exception 'Cash release not found' using errcode = 'P0002'; end if;
  if release.recipient_id <> caller then raise exception 'Only the cash recipient can acknowledge this release' using errcode = '42501'; end if;
  if release.status <> 'released' then raise exception 'Cash must be marked released before acknowledgement' using errcode = '22023'; end if;
  if release.acknowledged_at is null then
    update public.petty_cash_releases set acknowledged_by = caller, acknowledged_at = now() where id = release.id;
  end if;
end;
$$;

create or replace function public.guard_liquidation_release_acknowledgement()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if exists (
    select 1 from public.petty_cash_releases release
    where release.request_id = new.request_id
      and release.status = 'released'
      and release.acknowledged_at is null
  ) then
    raise exception 'Acknowledge every released cash tranche before submitting receipts' using errcode = '22023';
  end if;
  return new;
end;
$$;

drop trigger if exists liquidation_release_acknowledgement_guard on public.petty_cash_liquidations;
create trigger liquidation_release_acknowledgement_guard
before insert on public.petty_cash_liquidations
for each row execute function public.guard_liquidation_release_acknowledgement();

create or replace function public.adjust_department_fiscal_budget(
  p_budget_id uuid,
  p_adjusted_amount numeric,
  p_reason text,
  p_support_file_path text default null
) returns uuid language plpgsql security definer set search_path = public as $$
declare caller uuid := auth.uid(); budget public.department_fiscal_budgets; committed numeric := 0; adjustment_id uuid;
begin
  select * into budget from public.department_fiscal_budgets where id = p_budget_id for update;
  if not found then raise exception 'Annual budget not found' using errcode = 'P0002'; end if;
  if not public.is_department_budget_head(budget.org_id, caller) then raise exception 'Only the assigned Department Head can adjust the annual budget' using errcode = '42501'; end if;
  if budget.status <> 'locked' then raise exception 'Only a locked annual budget can be adjusted' using errcode = '22023'; end if;
  if p_adjusted_amount < 0 or nullif(btrim(p_reason), '') is null then raise exception 'Enter a valid adjusted amount and reason' using errcode = '22023'; end if;
  select coalesce(sum(amount), 0) into committed from public.budget_commitments where fiscal_budget_id = budget.id and status = 'active';
  if p_adjusted_amount < committed then raise exception 'Adjusted funding cannot be lower than active proposal commitments' using errcode = '22023'; end if;
  insert into public.department_budget_adjustments(fiscal_budget_id, previous_amount, adjusted_amount, reason, support_file_path, created_by)
  values (budget.id, budget.approved_amount, p_adjusted_amount, btrim(p_reason), nullif(btrim(p_support_file_path), ''), caller)
  returning id into adjustment_id;
  update public.department_fiscal_budgets set approved_amount = p_adjusted_amount, updated_at = now() where id = budget.id;
  insert into public.budget_ledger_entries(fiscal_budget_id, org_id, entry_type, amount, description, actor_id, metadata)
  values (budget.id, budget.org_id, 'budget_adjusted', abs(p_adjusted_amount - budget.approved_amount),
    'Annual appropriation adjusted: ' || btrim(p_reason), caller,
    jsonb_build_object('before', budget.approved_amount, 'after', p_adjusted_amount, 'adjustmentId', adjustment_id));
  insert into public.audit_events(actor_id, actor_name, entity_type, entity_id, action, before_data, after_data, reason, org_id)
  select caller, coalesce(full_name, 'Department Head'), 'department_budget', budget.id::text, 'department_budget.adjusted',
    jsonb_build_object('approvedAmount', budget.approved_amount), jsonb_build_object('approvedAmount', p_adjusted_amount),
    btrim(p_reason), budget.org_id from public.profiles where id = caller;
  return adjustment_id;
end;
$$;

create or replace function public.close_department_fiscal_budget(p_budget_id uuid, p_reason text)
returns void language plpgsql security definer set search_path = public as $$
declare caller uuid := auth.uid(); budget public.department_fiscal_budgets;
begin
  select * into budget from public.department_fiscal_budgets where id = p_budget_id for update;
  if not found then raise exception 'Annual budget not found' using errcode = 'P0002'; end if;
  if not public.is_department_budget_head(budget.org_id, caller) then raise exception 'Only the assigned Department Head can close the fiscal year' using errcode = '42501'; end if;
  if budget.status <> 'locked' then raise exception 'Only a locked annual budget can be closed' using errcode = '22023'; end if;
  if nullif(btrim(p_reason), '') is null then raise exception 'A fiscal close reason is required' using errcode = '22023'; end if;
  if exists (select 1 from public.petty_cash_requests where fiscal_budget_id = budget.id and status not in ('settled', 'rejected', 'cancelled')) then
    raise exception 'Settle or cancel every petty-cash request before closing this fiscal year' using errcode = '22023';
  end if;
  update public.department_fiscal_budgets set status = 'closed', closed_by = caller, closed_at = now(), updated_at = now() where id = budget.id;
  insert into public.budget_ledger_entries(fiscal_budget_id, org_id, entry_type, amount, description, actor_id)
  values (budget.id, budget.org_id, 'budget_closed', 0, 'Fiscal year closed: ' || btrim(p_reason), caller);
end;
$$;

create or replace function public.run_department_budget_maintenance()
returns int language plpgsql security definer set search_path = public as $$
declare changed int := 0;
begin
  with overdue as (
    update public.petty_cash_requests request set status = 'overdue_liquidation', updated_at = now()
    where request.status in ('released', 'changes_requested')
      and request.liquidation_due_at < now()
    returning request.*
  ), notified as (
    insert into public.notifications(user_id, type, title, message, task_id, financial_record_id, financial_record_type)
    select overdue.cash_recipient_id, 'petty_cash_liquidation_overdue', 'Petty-cash liquidation is overdue',
      'Submit the required receipts and return any unused cash immediately.', overdue.task_id, overdue.id, 'petty_cash_request' from overdue
    returning 1
  ) select count(*) into changed from notified;
  return changed;
end;
$$;

create or replace function public.guard_financial_work_completion()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.status = 'completed' and old.status is distinct from 'completed' and exists (
    select 1 from public.petty_cash_requests request
    where request.task_id = new.task_id
      and request.subtask_id = new.id
      and request.status not in ('settled', 'rejected', 'cancelled')
  ) then raise exception 'Settle all released or reserved cash before approving this funded subtask' using errcode = '22023'; end if;
  return new;
end;
$$;

drop trigger if exists subtask_financial_completion_guard on public.subtasks;
create trigger subtask_financial_completion_guard before update of status on public.subtasks
for each row execute function public.guard_financial_work_completion();

create or replace function public.guard_task_financial_completion()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.status = 'completed' and old.status is distinct from 'completed' and exists (
    select 1 from public.petty_cash_requests request where request.task_id = new.id
      and request.status not in ('settled', 'rejected', 'cancelled')
  ) then raise exception 'Settle all task and subtask cash before approving this task' using errcode = '22023'; end if;
  return new;
end;
$$;

drop trigger if exists task_financial_completion_guard on public.tasks;
create trigger task_financial_completion_guard before update of status on public.tasks
for each row execute function public.guard_task_financial_completion();

alter table public.department_budget_adjustments enable row level security;
drop policy if exists department_budget_adjustments_read on public.department_budget_adjustments;
create policy department_budget_adjustments_read on public.department_budget_adjustments for select to authenticated
using (exists (select 1 from public.department_fiscal_budgets budget where budget.id = fiscal_budget_id and public.can_view_department_budget(budget.org_id, auth.uid())));

revoke all on public.department_budget_adjustments from anon;
grant select on public.department_budget_adjustments to authenticated;
grant execute on function public.create_subtask_budget_allocation(uuid,uuid,uuid,numeric,text) to authenticated;
grant execute on function public.resubmit_petty_cash_request(uuid,numeric,text,date) to authenticated;
grant execute on function public.acknowledge_petty_cash_release(uuid) to authenticated;
grant execute on function public.adjust_department_fiscal_budget(uuid,numeric,text,text) to authenticated;
grant execute on function public.close_department_fiscal_budget(uuid,text) to authenticated;
grant execute on function public.run_department_budget_maintenance() to authenticated;

notify pgrst, 'reload schema';

commit;
