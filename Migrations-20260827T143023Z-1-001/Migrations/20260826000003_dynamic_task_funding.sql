-- Dynamic task funding: contextual requests, atomic reservations, optional
-- subtask caps, traceable budget-line selection, and complete financial audit.

begin;

alter table public.petty_cash_requests
  add column if not exists allocation_line_id uuid references public.work_budget_allocation_lines(id) on delete restrict,
  add column if not exists reservation_expires_at timestamptz,
  add column if not exists idempotency_key uuid;

alter table public.petty_cash_liquidations
  add column if not exists idempotency_key uuid;

alter table public.budget_ledger_entries
  add column if not exists task_id uuid references public.tasks(id) on delete restrict,
  add column if not exists subtask_id uuid references public.subtasks(id) on delete restrict,
  add column if not exists allocation_line_id uuid references public.work_budget_allocation_lines(id) on delete restrict,
  add column if not exists actor_role text,
  add column if not exists previous_state text,
  add column if not exists new_state text,
  add column if not exists reason text,
  add column if not exists correlation_key uuid;

create table if not exists public.petty_cash_request_attachments (
  id uuid primary key default gen_random_uuid(),
  request_id uuid not null references public.petty_cash_requests(id) on delete restrict,
  file_name text not null,
  file_path text not null,
  mime_type text not null,
  file_size bigint not null check (file_size >= 0),
  created_by uuid not null references public.profiles(id) on delete restrict,
  created_at timestamptz not null default now()
);

create index if not exists petty_cash_request_attachments_request_idx
  on public.petty_cash_request_attachments(request_id, created_at);

create unique index if not exists petty_cash_request_idempotency_uni
  on public.petty_cash_requests(requester_id, idempotency_key)
  where idempotency_key is not null;
create unique index if not exists petty_cash_liquidation_idempotency_uni
  on public.petty_cash_liquidations(request_id, idempotency_key)
  where idempotency_key is not null;
create unique index if not exists budget_ledger_command_idempotency_uni
  on public.budget_ledger_entries(actor_id, correlation_key, entry_type)
  where actor_id is not null and correlation_key is not null;
create index if not exists petty_cash_request_task_line_idx
  on public.petty_cash_requests(task_id, allocation_line_id, status, created_at desc);
create index if not exists budget_ledger_task_idx
  on public.budget_ledger_entries(task_id, created_at desc);

-- Existing allocation lines already carry the proposal line's accounting
-- classification. Backfill a canonical task-allocation line where it can be
-- determined without guessing across multiple lines.
update public.petty_cash_requests request
set allocation_line_id = coalesce(
  (
    select allocation.parent_allocation_line_id
    from public.work_budget_allocations allocation
    where allocation.id = request.allocation_id
      and allocation.subtask_id is not null
  ),
  (
    select line.id
    from public.work_budget_allocation_lines line
    where line.allocation_id = request.allocation_id
    order by line.position, line.id
    limit 1
  )
)
where request.allocation_line_id is null;

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
  add constraint petty_cash_requests_status_check check (status in (
    'draft', 'pending', 'pending_leader_review', 'leader_changes_requested',
    'pending_department_approval', 'department_changes_requested', 'approved',
    'scheduled_for_release', 'partially_released', 'released', 'rejected',
    'cancelled', 'expired', 'liquidation_draft', 'liquidation_submitted',
    'pending_leader_liquidation_review', 'pending_department_settlement',
    'changes_requested', 'overdue_liquidation', 'settled'
  ));

do $$
declare constraint_name text;
begin
  for constraint_name in
    select con.conname
    from pg_constraint con
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
    'petty_cash_released', 'expense_posted', 'cash_returned',
    'cash_request_created', 'cash_request_state_changed',
    'cash_release_state_changed', 'cash_release_acknowledged',
    'liquidation_submitted', 'liquidation_state_changed', 'receipt_attached',
    'request_evidence_attached',
    'subtask_cap_created', 'subtask_cap_changed', 'subtask_cap_removed',
    'financial_override'
  ));

-- A home department is an organization membership even when no additive
-- organization_memberships row exists. This fixes zero-row RLS results for
-- ordinary employees opening their proposal source/governance workspace.
create or replace function public.is_organization_member(
  target_organization uuid,
  caller_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select caller_id is not null and (
    exists (
      select 1 from public.profiles profile
      where profile.id = caller_id
        and profile.is_active
        and profile.org_id = target_organization
    )
    or exists (
      select 1
      from public.organization_memberships membership
      join public.profiles profile on profile.id = membership.user_id and profile.is_active
      where membership.organization_id = target_organization
        and membership.user_id = caller_id
    )
  );
$$;

create or replace function public.is_collaboration_participant(
  target_draft uuid,
  caller_id uuid
)
returns boolean
language plpgsql
stable
security definer
set search_path = public
as $$
declare draft_row public.proposal_collaboration_drafts;
begin
  if target_draft is null or caller_id is null then return false; end if;
  select * into draft_row from public.proposal_collaboration_drafts
  where id = target_draft and deleted_at is null;
  if not found then return false; end if;
  if public.auth_role(caller_id) = 'super_admin' then return true; end if;
  if draft_row.owner_user_id = caller_id
     or public.is_organization_approver(draft_row.owner_org_id, caller_id)
     or public.is_organization_member(draft_row.owner_org_id, caller_id) then
    return true;
  end if;
  if exists (
    select 1 from public.proposal_collaboration_orgs participant
    where participant.draft_id = target_draft
      and (
        public.is_organization_approver(participant.org_id, caller_id)
        or public.is_organization_member(participant.org_id, caller_id)
      )
  ) then return true; end if;
  if exists (
    select 1
    from public.projects project
    left join public.project_members member
      on member.project_id = project.id and member.user_id = caller_id
    where project.source_collaboration_draft_id = target_draft
      and (project.owner_id = caller_id or project.created_by = caller_id or member.user_id is not null)
  ) then return true; end if;
  return exists (
    select 1
    from public.tasks task
    where task.source_collaboration_draft_id = target_draft
      and task.deleted_at is null
      and (
        task.assigned_to = caller_id
        or task.recommendation_lead_id = caller_id
        or task.reviewer_id = caller_id
        or task.backup_reviewer_id = caller_id
        or coalesce(to_jsonb(task.team_member_ids), '[]'::jsonb) ? caller_id::text
        or exists (
          select 1 from public.subtasks subtask
          where subtask.task_id = task.id
            and coalesce(subtask.assigned_to_ids, '{}'::uuid[]) @> array[caller_id]
        )
      )
  );
end;
$$;

create or replace function public.cash_request_obligation(
  request_row public.petty_cash_requests
)
returns numeric
language sql
immutable
set search_path = public
as $$
  select case
    when request_row.status in ('rejected', 'cancelled', 'expired', 'draft') then 0::numeric
    when request_row.status = 'settled' then coalesce(request_row.actual_spent, 0)
    else coalesce(request_row.approved_amount, request_row.requested_amount, 0)
  end;
$$;

create or replace function public.task_budget_line_available(
  p_allocation_line_id uuid,
  p_exclude_request_id uuid default null
)
returns numeric
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  source_line public.work_budget_allocation_lines;
  task_allocation public.work_budget_allocations;
  cap_total numeric := 0;
  direct_obligation numeric := 0;
begin
  select * into source_line from public.work_budget_allocation_lines where id = p_allocation_line_id;
  if not found then return 0; end if;
  select * into task_allocation from public.work_budget_allocations
  where id = source_line.allocation_id and subtask_id is null and status = 'approved';
  if not found then return 0; end if;

  select coalesce(sum(cap.amount), 0) into cap_total
  from public.work_budget_allocations cap
  where cap.task_id = task_allocation.task_id
    and cap.commitment_id = task_allocation.commitment_id
    and cap.subtask_id is not null
    and cap.parent_allocation_line_id = source_line.id
    and cap.status in ('pending', 'approved');

  select coalesce(sum(public.cash_request_obligation(request)), 0) into direct_obligation
  from public.petty_cash_requests request
  join public.work_budget_allocations allocation on allocation.id = request.allocation_id
  where request.task_id = task_allocation.task_id
    and request.allocation_line_id = source_line.id
    and request.id is distinct from p_exclude_request_id
    and (
      allocation.subtask_id is null
      or allocation.status not in ('pending', 'approved')
    );

  return greatest(0, source_line.amount - cap_total - direct_obligation);
end;
$$;

create or replace function public.subtask_cap_available(
  p_cap_allocation_id uuid,
  p_exclude_request_id uuid default null
)
returns numeric
language plpgsql
stable
security definer
set search_path = public
as $$
declare cap public.work_budget_allocations; used numeric := 0;
begin
  select * into cap from public.work_budget_allocations
  where id = p_cap_allocation_id and subtask_id is not null and status in ('pending', 'approved');
  if not found then return 0; end if;
  select coalesce(sum(public.cash_request_obligation(request)), 0) into used
  from public.petty_cash_requests request
  where request.allocation_id = cap.id
    and request.id is distinct from p_exclude_request_id;
  return greatest(0, cap.amount - used);
end;
$$;

create or replace function public.get_task_funding_context(
  p_task_id uuid,
  p_subtask_id uuid default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  caller uuid := auth.uid();
  task_row public.tasks;
  task_allocation public.work_budget_allocations;
  cap public.work_budget_allocations;
  line_rows jsonb := '[]'::jsonb;
  task_available numeric := 0;
begin
  if not public.can_see_task(p_task_id, caller) then
    raise exception 'You cannot view funding for this task' using errcode = '42501';
  end if;
  select * into task_row from public.tasks where id = p_task_id and deleted_at is null;
  if not found then raise exception 'Task not found' using errcode = 'P0002'; end if;
  if p_subtask_id is not null and not exists (
    select 1 from public.subtasks where id = p_subtask_id and task_id = p_task_id
  ) then raise exception 'Subtask does not belong to this task' using errcode = '22023'; end if;
  select * into task_allocation from public.work_budget_allocations
  where task_id = p_task_id and subtask_id is null and status = 'approved';
  if not found then
    return jsonb_build_object('funded', false, 'taskId', p_task_id, 'subtaskId', p_subtask_id);
  end if;
  if p_subtask_id is not null then
    select * into cap from public.work_budget_allocations
    where task_id = p_task_id and subtask_id = p_subtask_id and status = 'approved';
  end if;
  select coalesce(jsonb_agg(jsonb_build_object(
      'id', line.id,
      'expenseClass', line.expense_class,
      'category', line.category,
      'particular', line.particular,
      'fundSource', line.fund_source,
      'amount', line.amount,
      'available', case
        when cap.id is not null and cap.parent_allocation_line_id = line.id
          then public.subtask_cap_available(cap.id)
        when cap.id is not null then 0
        else public.task_budget_line_available(line.id)
      end
    ) order by line.position), '[]'::jsonb),
    coalesce(sum(case
      when cap.id is not null and cap.parent_allocation_line_id = line.id
        then public.subtask_cap_available(cap.id)
      when cap.id is not null then 0
      else public.task_budget_line_available(line.id)
    end), 0)
  into line_rows, task_available
  from public.work_budget_allocation_lines line
  where line.allocation_id = task_allocation.id;
  return jsonb_build_object(
    'funded', true,
    'taskId', task_row.id,
    'subtaskId', p_subtask_id,
    'taskAllocationId', task_allocation.id,
    'taskBudget', task_allocation.amount,
    'available', task_available,
    'taskLeaderId', coalesce(task_row.assigned_to, task_row.recommendation_lead_id),
    'cap', case when cap.id is null then null else jsonb_build_object(
      'id', cap.id, 'amount', cap.amount, 'available', public.subtask_cap_available(cap.id),
      'allocationLineId', cap.parent_allocation_line_id, 'reason', cap.reason
    ) end,
    'lines', line_rows
  );
end;
$$;

create or replace function public.create_contextual_cash_request(
  p_task_id uuid,
  p_subtask_id uuid,
  p_allocation_line_id uuid,
  p_amount numeric,
  p_purpose text,
  p_needed_by date,
  p_idempotency_key uuid
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  caller uuid := auth.uid();
  existing_id uuid;
  task_row public.tasks;
  task_leader uuid;
  task_allocation public.work_budget_allocations;
  source_line public.work_budget_allocation_lines;
  cap public.work_budget_allocations;
  target_allocation public.work_budget_allocations;
  commitment public.budget_commitments;
  fiscal public.department_fiscal_budgets;
  available numeric := 0;
  next_status text;
  request_id uuid;
begin
  if caller is null then raise exception 'Not authenticated' using errcode = '42501'; end if;
  if p_idempotency_key is null then raise exception 'A request idempotency key is required' using errcode = '22023'; end if;
  select id into existing_id from public.petty_cash_requests
  where requester_id = caller and idempotency_key = p_idempotency_key;
  if existing_id is not null then return existing_id; end if;
  if p_amount <= 0 then raise exception 'Requested amount must be greater than zero' using errcode = '22023'; end if;
  if nullif(btrim(p_purpose), '') is null then raise exception 'Describe what this cash will purchase' using errcode = '22023'; end if;
  if p_allocation_line_id is null then raise exception 'Select a proposal budget line and fund source' using errcode = '22023'; end if;

  select * into task_row from public.tasks where id = p_task_id and deleted_at is null;
  if not found then raise exception 'Funded task not found' using errcode = 'P0002'; end if;
  task_leader := coalesce(task_row.assigned_to, task_row.recommendation_lead_id);
  if task_leader is null then raise exception 'This task has no Task Leader for endorsement routing' using errcode = '22023'; end if;
  if p_subtask_id is null then
    if caller <> task_leader then raise exception 'Only the Task Leader can submit a task-level request' using errcode = '42501'; end if;
  else
    if not exists (select 1 from public.subtasks where id = p_subtask_id and task_id = p_task_id) then
      raise exception 'Subtask does not belong to this task' using errcode = '22023';
    end if;
    if caller <> task_leader and not exists (
      select 1 from public.subtasks subtask where subtask.id = p_subtask_id
        and coalesce(subtask.assigned_to_ids, '{}'::uuid[]) @> array[caller]
    ) then raise exception 'Only the Task Leader or an assigned contributor can request cash for this subtask' using errcode = '42501'; end if;
  end if;

  select * into task_allocation from public.work_budget_allocations
  where task_id = p_task_id and subtask_id is null and status = 'approved' for update;
  if not found then raise exception 'This task has no approved proposal budget' using errcode = '22023'; end if;
  select * into source_line from public.work_budget_allocation_lines
  where id = p_allocation_line_id and allocation_id = task_allocation.id for update;
  if not found then raise exception 'Select a valid proposal budget line for this task' using errcode = '22023'; end if;
  select * into commitment from public.budget_commitments
  where id = task_allocation.commitment_id and status = 'active';
  if not found then raise exception 'The proposal budget is no longer active' using errcode = '22023'; end if;
  select * into fiscal from public.department_fiscal_budgets
  where id = commitment.fiscal_budget_id and status = 'locked' for update;
  if not found then raise exception 'The annual department budget is no longer open' using errcode = '22023'; end if;

  if p_subtask_id is not null then
    select * into cap from public.work_budget_allocations
    where task_id = p_task_id and subtask_id = p_subtask_id and status = 'approved' for update;
  end if;
  if cap.id is not null then
    if cap.parent_allocation_line_id is distinct from source_line.id then
      raise exception 'This subtask cap is reserved for a different proposal budget line' using errcode = '22023';
    end if;
    target_allocation := cap;
    available := public.subtask_cap_available(cap.id);
  else
    target_allocation := task_allocation;
    available := public.task_budget_line_available(source_line.id);
  end if;
  if p_amount > available then
    raise exception 'Only % remains available on % · %',
      to_char(available, 'FM999G999G999G990D00'), source_line.category, source_line.particular using errcode = '22023';
  end if;

  next_status := case when caller = task_leader then 'pending_department_approval' else 'pending_leader_review' end;
  insert into public.petty_cash_requests(
    fiscal_budget_id, commitment_id, allocation_id, allocation_line_id, org_id,
    task_id, subtask_id, requester_id, task_leader_id, cash_recipient_id,
    purpose, requested_amount, needed_by, status, reservation_expires_at, idempotency_key
  ) values (
    fiscal.id, commitment.id, target_allocation.id, source_line.id, fiscal.org_id,
    task_row.id, p_subtask_id, caller, task_leader, caller,
    btrim(p_purpose), p_amount, p_needed_by, next_status, now() + interval '7 days', p_idempotency_key
  ) returning id into request_id;

  if next_status = 'pending_leader_review' then
    insert into public.notifications(user_id, type, title, message, task_id, task_title, actor_id, actor_name, financial_record_id, financial_record_type)
    select task_leader, 'petty_cash_leader_review', 'Cash request needs your endorsement',
      coalesce(profile.full_name, 'A contributor') || ' requested ' || to_char(p_amount, 'FM999G999G999G990D00') ||
      ' for ' || btrim(p_purpose) || ' in "' || task_row.title || '".',
      task_row.id, task_row.title, caller, coalesce(profile.full_name, ''), request_id, 'petty_cash_request'
    from public.profiles profile where profile.id = caller and task_leader <> caller;
  else
    insert into public.notifications(user_id, type, title, message, task_id, task_title, actor_id, actor_name, financial_record_id, financial_record_type)
    select approver_id, 'petty_cash_department_approval', 'Cash request needs fiscal authorization',
      coalesce(profile.full_name, 'A Task Leader') || ' requested ' || to_char(p_amount, 'FM999G999G999G990D00') ||
      ' for ' || btrim(p_purpose) || ' in "' || task_row.title || '".',
      task_row.id, task_row.title, caller, coalesce(profile.full_name, ''), request_id, 'petty_cash_request'
    from public.organization_approver_ids(task_row.org_id) approver_id
    left join public.profiles profile on profile.id = caller
    where approver_id <> caller;
  end if;
  return request_id;
exception
  when unique_violation then
    select id into existing_id from public.petty_cash_requests
    where requester_id = caller and idempotency_key = p_idempotency_key;
    if existing_id is not null then return existing_id; end if;
    raise;
end;
$$;

create or replace function public.resubmit_contextual_cash_request(
  p_request_id uuid,
  p_allocation_line_id uuid,
  p_amount numeric,
  p_purpose text,
  p_needed_by date
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  caller uuid := auth.uid();
  request public.petty_cash_requests;
  allocation public.work_budget_allocations;
  source_line public.work_budget_allocation_lines;
  available numeric := 0;
  next_status text;
begin
  select * into request from public.petty_cash_requests where id = p_request_id for update;
  if not found then raise exception 'Cash request not found' using errcode = 'P0002'; end if;
  if request.requester_id <> caller then raise exception 'Only the requester can correct this request' using errcode = '42501'; end if;
  if request.status not in ('leader_changes_requested', 'department_changes_requested') then
    raise exception 'This request is not awaiting corrections' using errcode = '22023';
  end if;
  if p_amount <= 0 or nullif(btrim(p_purpose), '') is null then
    raise exception 'Enter a positive amount and purchase purpose' using errcode = '22023';
  end if;
  select * into source_line from public.work_budget_allocation_lines where id = p_allocation_line_id for update;
  if not found or source_line.allocation_id <> (
    select id from public.work_budget_allocations
    where task_id = request.task_id and subtask_id is null and status = 'approved'
  ) then raise exception 'Select a valid proposal budget line for this task' using errcode = '22023'; end if;
  select * into allocation from public.work_budget_allocations where id = request.allocation_id for update;
  if allocation.subtask_id is not null and allocation.status = 'approved' then
    if allocation.parent_allocation_line_id is distinct from source_line.id then
      raise exception 'This subtask cap is reserved for a different proposal budget line' using errcode = '22023';
    end if;
    available := public.subtask_cap_available(allocation.id, request.id);
  else
    available := public.task_budget_line_available(source_line.id, request.id);
  end if;
  if p_amount > available then raise exception 'The selected budget line has only % available', to_char(available, 'FM999G999G999G990D00') using errcode = '22023'; end if;
  next_status := case when request.requester_id = request.task_leader_id then 'pending_department_approval' else 'pending_leader_review' end;
  update public.petty_cash_requests set
    allocation_line_id = source_line.id,
    requested_amount = p_amount,
    purpose = btrim(p_purpose),
    needed_by = p_needed_by,
    status = next_status,
    approved_amount = null,
    approved_by = null,
    approval_reason = null,
    decided_at = null,
    leader_decided_by = null,
    leader_decision_reason = null,
    leader_decided_at = null,
    department_decision_reason = null,
    reservation_expires_at = now() + interval '7 days',
    updated_at = now()
  where id = request.id;
end;
$$;

create or replace function public.set_subtask_budget_cap(
  p_task_id uuid,
  p_subtask_id uuid,
  p_parent_allocation_line_id uuid,
  p_amount numeric,
  p_reason text,
  p_idempotency_key uuid
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  caller uuid := auth.uid();
  task_row public.tasks;
  parent_allocation public.work_budget_allocations;
  parent_line public.work_budget_allocation_lines;
  cap public.work_budget_allocations;
  cap_id uuid;
  available numeric := 0;
  settled numeric := 0;
  event_type text;
  old_amount numeric;
begin
  if p_amount <= 0 then raise exception 'Cap amount must be greater than zero' using errcode = '22023'; end if;
  if nullif(btrim(p_reason), '') is null then raise exception 'Explain why this subtask needs a protected cap' using errcode = '22023'; end if;
  select * into task_row from public.tasks where id = p_task_id and deleted_at is null;
  if not found then raise exception 'Task not found' using errcode = 'P0002'; end if;
  if caller is distinct from coalesce(task_row.assigned_to, task_row.recommendation_lead_id) then
    raise exception 'Only the Task Leader can set a subtask cap' using errcode = '42501';
  end if;
  if not exists (select 1 from public.subtasks where id = p_subtask_id and task_id = p_task_id) then
    raise exception 'Subtask does not belong to this task' using errcode = '22023';
  end if;
  select * into parent_allocation from public.work_budget_allocations
  where task_id = p_task_id and subtask_id is null and status = 'approved' for update;
  if not found then raise exception 'This task has no approved proposal budget' using errcode = '22023'; end if;
  select * into parent_line from public.work_budget_allocation_lines
  where id = p_parent_allocation_line_id and allocation_id = parent_allocation.id for update;
  if not found then raise exception 'Select a valid proposal budget line for this task' using errcode = '22023'; end if;
  select * into cap from public.work_budget_allocations
  where task_id = p_task_id and subtask_id = p_subtask_id and status in ('pending', 'approved') for update;
  available := public.task_budget_line_available(parent_line.id)
    + case when cap.parent_allocation_line_id = parent_line.id then coalesce(cap.amount, 0) else 0 end;
  if p_amount > available then raise exception 'Only % is available to protect on this budget line', to_char(available, 'FM999G999G999G990D00') using errcode = '22023'; end if;
  if cap.id is not null then
    if exists (
      select 1 from public.petty_cash_requests request
      where request.allocation_id = cap.id
        and request.status not in ('draft', 'rejected', 'cancelled', 'expired', 'settled')
    ) then raise exception 'This cap has an active cash request and cannot be edited' using errcode = '22023'; end if;
    select coalesce(sum(actual_spent), 0) into settled from public.petty_cash_requests
    where allocation_id = cap.id and status = 'settled';
    if p_amount < settled then raise exception 'The cap cannot be lower than its settled spending of %', to_char(settled, 'FM999G999G999G990D00') using errcode = '22023'; end if;
    old_amount := cap.amount;
    update public.work_budget_allocations set
      parent_allocation_line_id = parent_line.id,
      amount = p_amount,
      status = 'approved',
      reason = btrim(p_reason),
      decided_by = caller,
      decision_reason = 'Protected by Task Leader',
      decided_at = now(),
      updated_at = now()
    where id = cap.id returning id into cap_id;
    update public.work_budget_allocation_lines set
      expense_class = parent_line.expense_class,
      category = parent_line.category,
      particular = parent_line.particular,
      quantity = 1,
      unit = 'cap',
      unit_cost = p_amount,
      amount = p_amount,
      fund_source = parent_line.fund_source
    where allocation_id = cap.id;
    event_type := 'subtask_cap_changed';
  else
    insert into public.work_budget_allocations(
      commitment_id, task_id, subtask_id, parent_allocation_line_id, amount,
      status, reason, requested_by, decided_by, decision_reason, requested_at, decided_at
    ) values (
      parent_allocation.commitment_id, p_task_id, p_subtask_id, parent_line.id, p_amount,
      'approved', btrim(p_reason), caller, caller, 'Protected by Task Leader', now(), now()
    ) returning id into cap_id;
    insert into public.work_budget_allocation_lines(
      allocation_id, draft_task_key, expense_class, category, particular,
      quantity, unit, unit_cost, amount, fund_source, position
    ) values (
      cap_id, parent_line.draft_task_key, parent_line.expense_class, parent_line.category,
      parent_line.particular, 1, 'cap', p_amount, p_amount, parent_line.fund_source, 0
    );
    event_type := 'subtask_cap_created';
    old_amount := 0;
  end if;
  insert into public.budget_ledger_entries(
    fiscal_budget_id, org_id, commitment_id, allocation_id, task_id, subtask_id,
    allocation_line_id, entry_type, amount, description, actor_id, actor_role,
    previous_state, new_state, reason, correlation_key, metadata
  ) select commitment.fiscal_budget_id, task_row.org_id, parent_allocation.commitment_id,
      cap_id, p_task_id, p_subtask_id, parent_line.id, event_type,
      abs(p_amount - coalesce(old_amount, 0)), 'Subtask funding cap protected by Task Leader',
      caller, profile.role::text, coalesce(old_amount, 0)::text, p_amount::text,
      btrim(p_reason), p_idempotency_key,
      jsonb_build_object('fundSource', parent_line.fund_source, 'category', parent_line.category, 'particular', parent_line.particular)
    from public.budget_commitments commitment
    left join public.profiles profile on profile.id = caller
    where commitment.id = parent_allocation.commitment_id
  on conflict (actor_id, correlation_key, entry_type) where actor_id is not null and correlation_key is not null do nothing;
  return cap_id;
end;
$$;

create or replace function public.remove_subtask_budget_cap(
  p_cap_allocation_id uuid,
  p_reason text,
  p_idempotency_key uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare caller uuid := auth.uid(); cap public.work_budget_allocations; task_row public.tasks; unused numeric;
begin
  select * into cap from public.work_budget_allocations
  where id = p_cap_allocation_id and subtask_id is not null and status in ('pending', 'approved') for update;
  if not found then raise exception 'Active subtask cap not found' using errcode = 'P0002'; end if;
  select * into task_row from public.tasks where id = cap.task_id;
  if caller is distinct from coalesce(task_row.assigned_to, task_row.recommendation_lead_id) then
    raise exception 'Only the Task Leader can remove a subtask cap' using errcode = '42501';
  end if;
  if nullif(btrim(p_reason), '') is null then raise exception 'Explain why the cap is being removed' using errcode = '22023'; end if;
  if exists (
    select 1 from public.petty_cash_requests request
    where request.allocation_id = cap.id
      and request.status not in ('draft', 'rejected', 'cancelled', 'expired', 'settled')
  ) then raise exception 'This cap has an active cash request and cannot be removed' using errcode = '22023'; end if;
  unused := public.subtask_cap_available(cap.id);
  update public.work_budget_allocations set status = 'cancelled', decision_reason = btrim(p_reason), updated_at = now() where id = cap.id;
  insert into public.budget_ledger_entries(
    fiscal_budget_id, org_id, commitment_id, allocation_id, task_id, subtask_id,
    allocation_line_id, entry_type, amount, description, actor_id, actor_role,
    previous_state, new_state, reason, correlation_key
  ) select commitment.fiscal_budget_id, task_row.org_id, cap.commitment_id, cap.id,
      cap.task_id, cap.subtask_id, cap.parent_allocation_line_id, 'subtask_cap_removed',
      unused, 'Unused subtask cap returned to shared task funding', caller,
      profile.role::text, 'approved', 'cancelled', btrim(p_reason), p_idempotency_key
    from public.budget_commitments commitment
    left join public.profiles profile on profile.id = caller
    where commitment.id = cap.commitment_id
  on conflict (actor_id, correlation_key, entry_type) where actor_id is not null and correlation_key is not null do nothing;
end;
$$;

create or replace function public.cancel_contextual_cash_request(
  p_request_id uuid,
  p_reason text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare caller uuid := auth.uid(); request public.petty_cash_requests;
begin
  select * into request from public.petty_cash_requests where id = p_request_id for update;
  if not found then raise exception 'Cash request not found' using errcode = 'P0002'; end if;
  if request.requester_id <> caller and not public.is_department_budget_approver(request.org_id, caller) then
    raise exception 'Only the requester or a fiscal approver can cancel this request' using errcode = '42501';
  end if;
  if request.status in ('partially_released', 'released', 'liquidation_submitted', 'pending_leader_liquidation_review', 'pending_department_settlement', 'changes_requested', 'overdue_liquidation', 'settled') then
    raise exception 'Released cash must be liquidated rather than cancelled' using errcode = '22023';
  end if;
  if request.status in ('rejected', 'cancelled', 'expired') then return; end if;
  if nullif(btrim(p_reason), '') is null then raise exception 'A cancellation reason is required' using errcode = '22023'; end if;
  update public.petty_cash_releases set status = 'cancelled'
  where request_id = request.id and status = 'scheduled';
  update public.petty_cash_requests set status = 'cancelled', approval_reason = btrim(p_reason), updated_at = now()
  where id = request.id;
end;
$$;

create or replace function public.add_cash_request_attachment(
  p_request_id uuid,
  p_file_name text,
  p_file_path text,
  p_mime_type text,
  p_file_size bigint
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare caller uuid := auth.uid(); request public.petty_cash_requests; attachment_id uuid; actor_role_value text;
begin
  select * into request from public.petty_cash_requests where id = p_request_id;
  if not found then raise exception 'Cash request not found' using errcode = 'P0002'; end if;
  if request.requester_id <> caller then raise exception 'Only the requester can attach purchase evidence' using errcode = '42501'; end if;
  if nullif(btrim(p_file_name), '') is null or nullif(btrim(p_file_path), '') is null or p_file_size < 0 then
    raise exception 'Attachment metadata is invalid' using errcode = '22023';
  end if;
  insert into public.petty_cash_request_attachments(request_id, file_name, file_path, mime_type, file_size, created_by)
  values (request.id, btrim(p_file_name), btrim(p_file_path), coalesce(nullif(btrim(p_mime_type), ''), 'application/octet-stream'), p_file_size, caller)
  returning id into attachment_id;
  select role::text into actor_role_value from public.profiles where id = caller;
  insert into public.budget_ledger_entries(
    fiscal_budget_id, org_id, commitment_id, allocation_id, petty_cash_request_id,
    task_id, subtask_id, allocation_line_id, entry_type, amount, description,
    actor_id, actor_role, new_state, metadata
  ) values (
    request.fiscal_budget_id, request.org_id, request.commitment_id, request.allocation_id, request.id,
    request.task_id, request.subtask_id, request.allocation_line_id, 'request_evidence_attached',
    0, 'Purchase quote or supporting evidence attached', caller, actor_role_value, 'attached',
    jsonb_build_object('attachmentId', attachment_id, 'fileName', p_file_name, 'filePath', p_file_path)
  );
  return attachment_id;
end;
$$;

-- Compatibility entry points now use the reservation-safe contextual engine.
create or replace function public.create_petty_cash_request(
  p_allocation_id uuid,
  p_amount numeric,
  p_purpose text,
  p_needed_by date
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare allocation public.work_budget_allocations; source_line_id uuid; line_count int;
begin
  select * into allocation from public.work_budget_allocations where id = p_allocation_id and status = 'approved';
  if not found then raise exception 'Choose an approved task or subtask budget' using errcode = '22023'; end if;
  if allocation.subtask_id is not null then
    source_line_id := allocation.parent_allocation_line_id;
  else
    select count(*), (array_agg(id order by position, id))[1] into line_count, source_line_id
    from public.work_budget_allocation_lines where allocation_id = allocation.id;
    if line_count <> 1 then raise exception 'Select the proposal budget line and fund source from the task funding card' using errcode = '22023'; end if;
  end if;
  return public.create_contextual_cash_request(
    allocation.task_id, allocation.subtask_id, source_line_id, p_amount,
    p_purpose, p_needed_by, gen_random_uuid()
  );
end;
$$;

create or replace function public.resubmit_petty_cash_request(
  p_request_id uuid,
  p_amount numeric,
  p_purpose text,
  p_needed_by date
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare source_line_id uuid;
begin
  select allocation_line_id into source_line_id from public.petty_cash_requests where id = p_request_id;
  if source_line_id is null then raise exception 'Select a proposal budget line before resubmitting this request' using errcode = '22023'; end if;
  perform public.resubmit_contextual_cash_request(p_request_id, source_line_id, p_amount, p_purpose, p_needed_by);
end;
$$;

create or replace function public.submit_contextual_cash_liquidation(
  p_request_id uuid,
  p_declared_spent numeric,
  p_note text,
  p_receipts jsonb,
  p_idempotency_key uuid
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare existing_id uuid; created_id uuid;
begin
  if p_idempotency_key is null then raise exception 'A liquidation idempotency key is required' using errcode = '22023'; end if;
  select id into existing_id from public.petty_cash_liquidations
  where request_id = p_request_id and idempotency_key = p_idempotency_key;
  if existing_id is not null then return existing_id; end if;
  created_id := public.submit_petty_cash_liquidation(p_request_id, p_declared_spent, p_note, p_receipts);
  update public.petty_cash_liquidations set idempotency_key = p_idempotency_key where id = created_id;
  return created_id;
exception
  when unique_violation then
    select id into existing_id from public.petty_cash_liquidations
    where request_id = p_request_id and idempotency_key = p_idempotency_key;
    if existing_id is not null then return existing_id; end if;
    raise;
end;
$$;

create or replace function public.audit_cash_request_change()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare actor uuid := auth.uid(); actor_role_value text;
begin
  select role::text into actor_role_value from public.profiles where id = actor;
  if tg_op = 'INSERT' then
    insert into public.budget_ledger_entries(
      fiscal_budget_id, org_id, commitment_id, allocation_id, petty_cash_request_id,
      task_id, subtask_id, allocation_line_id, entry_type, amount, description,
      actor_id, actor_role, new_state, reason, correlation_key, metadata
    ) values (
      new.fiscal_budget_id, new.org_id, new.commitment_id, new.allocation_id, new.id,
      new.task_id, new.subtask_id, new.allocation_line_id, 'cash_request_created',
      new.requested_amount, 'Cash requested and temporarily reserved', actor,
      actor_role_value, new.status, new.purpose, new.idempotency_key,
      jsonb_build_object('neededBy', new.needed_by, 'reservationExpiresAt', new.reservation_expires_at)
    );
  elsif new.status is distinct from old.status then
    insert into public.budget_ledger_entries(
      fiscal_budget_id, org_id, commitment_id, allocation_id, petty_cash_request_id,
      task_id, subtask_id, allocation_line_id, entry_type, amount, description,
      actor_id, actor_role, previous_state, new_state, reason, metadata
    ) values (
      new.fiscal_budget_id, new.org_id, new.commitment_id, new.allocation_id, new.id,
      new.task_id, new.subtask_id, new.allocation_line_id, 'cash_request_state_changed',
      case when new.status = 'settled' then coalesce(new.actual_spent, 0) else coalesce(new.approved_amount, new.requested_amount) end,
      'Cash request state changed', actor, actor_role_value, old.status, new.status,
      coalesce(new.department_decision_reason, new.leader_decision_reason, new.approval_reason),
      jsonb_build_object('returnedAmount', new.returned_amount, 'releasedAmount', new.released_amount)
    );
  end if;
  return new;
end;
$$;

drop trigger if exists petty_cash_request_audit on public.petty_cash_requests;
create trigger petty_cash_request_audit
after insert or update on public.petty_cash_requests
for each row execute function public.audit_cash_request_change();

create or replace function public.audit_cash_release_change()
returns trigger language plpgsql security definer set search_path = public as $$
declare request public.petty_cash_requests; actor uuid := auth.uid(); actor_role_value text;
begin
  select * into request from public.petty_cash_requests where id = new.request_id;
  select role::text into actor_role_value from public.profiles where id = actor;
  if new.status is distinct from old.status then
    insert into public.budget_ledger_entries(
      fiscal_budget_id, org_id, commitment_id, allocation_id, petty_cash_request_id,
      task_id, subtask_id, allocation_line_id, entry_type, amount, description,
      actor_id, actor_role, previous_state, new_state, metadata
    ) values (
      request.fiscal_budget_id, request.org_id, request.commitment_id, request.allocation_id, request.id,
      request.task_id, request.subtask_id, request.allocation_line_id, 'cash_release_state_changed',
      new.amount, 'Cash release state changed', actor, actor_role_value, old.status, new.status,
      jsonb_build_object('releaseId', new.id, 'scheduledDate', new.scheduled_date, 'recipientId', new.recipient_id)
    );
  end if;
  if new.acknowledged_at is not null and old.acknowledged_at is null then
    insert into public.budget_ledger_entries(
      fiscal_budget_id, org_id, commitment_id, allocation_id, petty_cash_request_id,
      task_id, subtask_id, allocation_line_id, entry_type, amount, description,
      actor_id, actor_role, previous_state, new_state, metadata
    ) values (
      request.fiscal_budget_id, request.org_id, request.commitment_id, request.allocation_id, request.id,
      request.task_id, request.subtask_id, request.allocation_line_id, 'cash_release_acknowledged',
      new.amount, 'Cash recipient acknowledged release', actor, actor_role_value,
      'released', 'acknowledged', jsonb_build_object('releaseId', new.id)
    );
  end if;
  return new;
end;
$$;

drop trigger if exists petty_cash_release_audit on public.petty_cash_releases;
create trigger petty_cash_release_audit
after update on public.petty_cash_releases
for each row execute function public.audit_cash_release_change();

create or replace function public.audit_liquidation_change()
returns trigger language plpgsql security definer set search_path = public as $$
declare request public.petty_cash_requests; actor uuid := auth.uid(); actor_role_value text;
begin
  select * into request from public.petty_cash_requests where id = new.request_id;
  select role::text into actor_role_value from public.profiles where id = actor;
  insert into public.budget_ledger_entries(
    fiscal_budget_id, org_id, commitment_id, allocation_id, petty_cash_request_id,
    task_id, subtask_id, allocation_line_id, entry_type, amount, description,
    actor_id, actor_role, previous_state, new_state, reason, correlation_key, metadata
  ) values (
    request.fiscal_budget_id, request.org_id, request.commitment_id, request.allocation_id, request.id,
    request.task_id, request.subtask_id, request.allocation_line_id,
    case when tg_op = 'INSERT' then 'liquidation_submitted' else 'liquidation_state_changed' end,
    new.declared_spent, case when tg_op = 'INSERT' then 'Receipt package submitted' else 'Liquidation state changed' end,
    actor, actor_role_value, case when tg_op = 'UPDATE' then old.status end, new.status,
    coalesce(new.department_decision_reason, new.leader_decision_reason, new.decision_reason, new.note),
    new.idempotency_key,
    jsonb_build_object('liquidationId', new.id, 'version', new.version, 'returnedAmount', new.returned_amount)
  ) on conflict (actor_id, correlation_key, entry_type) where actor_id is not null and correlation_key is not null do nothing;
  return new;
end;
$$;

drop trigger if exists petty_cash_liquidation_audit on public.petty_cash_liquidations;
create trigger petty_cash_liquidation_audit
after insert or update of status on public.petty_cash_liquidations
for each row execute function public.audit_liquidation_change();

create or replace function public.audit_receipt_attachment()
returns trigger language plpgsql security definer set search_path = public as $$
declare request public.petty_cash_requests; actor uuid := auth.uid(); actor_role_value text;
begin
  select request_row.* into request
  from public.petty_cash_liquidations liquidation
  join public.petty_cash_requests request_row on request_row.id = liquidation.request_id
  where liquidation.id = new.liquidation_id;
  select role::text into actor_role_value from public.profiles where id = actor;
  insert into public.budget_ledger_entries(
    fiscal_budget_id, org_id, commitment_id, allocation_id, petty_cash_request_id,
    task_id, subtask_id, allocation_line_id, entry_type, amount, description,
    actor_id, actor_role, new_state, metadata
  ) values (
    request.fiscal_budget_id, request.org_id, request.commitment_id, request.allocation_id, request.id,
    request.task_id, request.subtask_id, request.allocation_line_id, 'receipt_attached',
    new.amount, 'Receipt evidence attached', actor, actor_role_value, 'attached',
    jsonb_build_object('receiptId', new.id, 'vendor', new.vendor, 'receiptNumber', new.receipt_number,
      'fileName', new.file_name, 'filePath', new.file_path, 'overrideReason', new.override_reason)
  );
  return new;
end;
$$;

drop trigger if exists petty_cash_receipt_audit on public.petty_cash_receipts;
create trigger petty_cash_receipt_audit
after insert on public.petty_cash_receipts
for each row execute function public.audit_receipt_attachment();

create or replace function public.prevent_budget_ledger_mutation()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  raise exception 'Financial audit ledger entries are append-only' using errcode = '42501';
end;
$$;

drop trigger if exists budget_ledger_append_only on public.budget_ledger_entries;
create trigger budget_ledger_append_only
before update or delete on public.budget_ledger_entries
for each row execute function public.prevent_budget_ledger_mutation();

alter table public.petty_cash_request_attachments enable row level security;
drop policy if exists petty_cash_request_attachments_read on public.petty_cash_request_attachments;
create policy petty_cash_request_attachments_read on public.petty_cash_request_attachments
for select to authenticated using (exists (
  select 1 from public.petty_cash_requests request
  where request.id = request_id and (
    request.requester_id = auth.uid()
    or request.cash_recipient_id = auth.uid()
    or request.task_leader_id = auth.uid()
    or public.is_department_budget_approver(request.org_id, auth.uid())
  )
));

create or replace function public.run_department_budget_maintenance()
returns int
language plpgsql
security definer
set search_path = public
as $$
declare changed int := 0; expired_count int := 0;
begin
  with expired as (
    update public.petty_cash_requests request
    set status = 'expired', updated_at = now()
    where request.status in (
      'pending', 'pending_leader_review', 'leader_changes_requested',
      'pending_department_approval', 'department_changes_requested'
    )
      and request.reservation_expires_at is not null
      and request.reservation_expires_at < now()
    returning request.*
  ), notified as (
    insert into public.notifications(user_id, type, title, message, task_id, financial_record_id, financial_record_type)
    select expired.requester_id, 'petty_cash_request_expired', 'Cash-request reservation expired',
      'The temporary reservation expired. Submit a new request if the purchase is still needed.',
      expired.task_id, expired.id, 'petty_cash_request' from expired
    returning 1
  ) select count(*) into expired_count from notified;

  with overdue as (
    update public.petty_cash_requests request set status = 'overdue_liquidation', updated_at = now()
    where request.status in ('released', 'changes_requested')
      and request.liquidation_due_at < now()
    returning request.*
  ), notified as (
    insert into public.notifications(user_id, type, title, message, task_id, financial_record_id, financial_record_type)
    select overdue.cash_recipient_id, 'petty_cash_liquidation_overdue', 'Cash liquidation is overdue',
      'Submit the required receipts and return any unused cash immediately.', overdue.task_id, overdue.id, 'petty_cash_request'
    from overdue returning 1
  ) select count(*) into changed from notified;
  return changed + expired_count;
end;
$$;

revoke all on function public.cash_request_obligation(public.petty_cash_requests) from public, anon;
revoke all on function public.task_budget_line_available(uuid, uuid) from public, anon;
revoke all on function public.subtask_cap_available(uuid, uuid) from public, anon;
revoke all on function public.get_task_funding_context(uuid, uuid) from public, anon;
revoke all on function public.create_contextual_cash_request(uuid, uuid, uuid, numeric, text, date, uuid) from public, anon;
revoke all on function public.resubmit_contextual_cash_request(uuid, uuid, numeric, text, date) from public, anon;
revoke all on function public.set_subtask_budget_cap(uuid, uuid, uuid, numeric, text, uuid) from public, anon;
revoke all on function public.remove_subtask_budget_cap(uuid, text, uuid) from public, anon;
revoke all on function public.cancel_contextual_cash_request(uuid, text) from public, anon;
revoke all on function public.add_cash_request_attachment(uuid, text, text, text, bigint) from public, anon;
revoke all on function public.submit_contextual_cash_liquidation(uuid, numeric, text, jsonb, uuid) from public, anon;

grant execute on function public.get_task_funding_context(uuid, uuid) to authenticated;
grant execute on function public.create_contextual_cash_request(uuid, uuid, uuid, numeric, text, date, uuid) to authenticated;
grant execute on function public.resubmit_contextual_cash_request(uuid, uuid, numeric, text, date) to authenticated;
grant execute on function public.set_subtask_budget_cap(uuid, uuid, uuid, numeric, text, uuid) to authenticated;
grant execute on function public.remove_subtask_budget_cap(uuid, text, uuid) to authenticated;
grant execute on function public.cancel_contextual_cash_request(uuid, text) to authenticated;
grant execute on function public.add_cash_request_attachment(uuid, text, text, text, bigint) to authenticated;
grant execute on function public.submit_contextual_cash_liquidation(uuid, numeric, text, jsonb, uuid) to authenticated;
grant select on public.petty_cash_request_attachments to authenticated;

do $$
begin
  alter publication supabase_realtime add table public.petty_cash_request_attachments;
exception when duplicate_object then null; when undefined_object then null;
end;
$$;

notify pgrst, 'reload schema';

commit;
