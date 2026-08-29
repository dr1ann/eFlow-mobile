-- Makes an approved task budget a controlled funding envelope for its subtasks.
-- A Task Leader can immediately distribute that already-approved envelope, while
-- the database prevents the same money being used by both a parent-task request
-- and one or more subtask allocations.

begin;

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
  parent_cash_committed numeric := 0;
begin
  if new.subtask_id is null or new.status not in ('pending', 'approved') then
    return new;
  end if;

  select * into parent_allocation
  from public.work_budget_allocations
  where commitment_id = new.commitment_id
    and task_id = new.task_id
    and subtask_id is null
    and status = 'approved'
  for update;
  if not found then
    raise exception 'The task has no approved proposal allocation' using errcode = '22023';
  end if;

  select coalesce(sum(amount), 0) into allocated
  from public.work_budget_allocations
  where commitment_id = new.commitment_id
    and task_id = new.task_id
    and subtask_id is not null
    and status in ('pending', 'approved')
    and id <> new.id;

  -- Cash requested directly against a parent task uses the same envelope and
  -- cannot later be delegated to a subtask.
  select coalesce(sum(
    case when status = 'settled' then coalesce(actual_spent, 0)
      else coalesce(approved_amount, requested_amount, 0)
    end
  ), 0) into parent_cash_committed
  from public.petty_cash_requests
  where allocation_id = parent_allocation.id
    and status not in ('draft', 'rejected', 'cancelled', 'leader_changes_requested', 'department_changes_requested');

  if allocated + parent_cash_committed + new.amount > parent_allocation.amount then
    raise exception 'The task budget has already been committed to subtask funding or task-level petty cash' using errcode = '22023';
  end if;

  if new.parent_allocation_line_id is not null then
    select * into parent_line
    from public.work_budget_allocation_lines
    where id = new.parent_allocation_line_id
      and allocation_id = parent_allocation.id;
    if not found then
      raise exception 'Choose a budget particular from this task allocation' using errcode = '22023';
    end if;

    select coalesce(sum(amount), 0) into allocated
    from public.work_budget_allocations
    where parent_allocation_line_id = parent_line.id
      and status in ('pending', 'approved')
      and id <> new.id;
    if allocated + new.amount > parent_line.amount then
      raise exception 'This budget particular does not have enough unallocated funding' using errcode = '22023';
    end if;
  end if;

  return new;
end;
$$;

drop trigger if exists work_budget_allocation_caps_guard on public.work_budget_allocations;
create trigger work_budget_allocation_caps_guard
before insert or update of amount, status, parent_allocation_line_id
on public.work_budget_allocations
for each row execute function public.guard_work_budget_allocation_caps();

create or replace function public.guard_petty_cash_allocation_capacity()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  allocation public.work_budget_allocations;
  parent_allocation public.work_budget_allocations;
  child_allocated numeric := 0;
  parent_cash_committed numeric := 0;
  own_cash_committed numeric := 0;
  new_amount numeric := 0;
begin
  select * into allocation
  from public.work_budget_allocations
  where id = new.allocation_id;
  if not found then return new; end if;

  if new.status in ('draft', 'rejected', 'cancelled', 'leader_changes_requested', 'department_changes_requested') then
    return new;
  end if;

  new_amount := case
    when new.status = 'settled' then coalesce(new.actual_spent, 0)
    else coalesce(new.approved_amount, new.requested_amount, 0)
  end;

  select coalesce(sum(case when status = 'settled' then coalesce(actual_spent, 0)
    else coalesce(approved_amount, requested_amount, 0) end), 0)
  into own_cash_committed
  from public.petty_cash_requests
  where allocation_id = allocation.id
    and id <> new.id
    and status not in ('draft', 'rejected', 'cancelled', 'leader_changes_requested', 'department_changes_requested');
  if own_cash_committed + new_amount > allocation.amount then
    raise exception 'This work allocation does not have enough remaining funds' using errcode = '22023';
  end if;

  if allocation.subtask_id is not null then
    select * into parent_allocation
    from public.work_budget_allocations
    where commitment_id = allocation.commitment_id
      and task_id = allocation.task_id
      and subtask_id is null
      and status = 'approved';
  else
    parent_allocation := allocation;
  end if;
  if parent_allocation.id is null then return new; end if;

  select coalesce(sum(amount), 0) into child_allocated
  from public.work_budget_allocations
  where commitment_id = parent_allocation.commitment_id
    and task_id = parent_allocation.task_id
    and subtask_id is not null
    and status in ('pending', 'approved')
    and id <> allocation.id;

  if allocation.subtask_id is not null then
    child_allocated := child_allocated + allocation.amount;
  end if;

  select coalesce(sum(case when status = 'settled' then coalesce(actual_spent, 0)
    else coalesce(approved_amount, requested_amount, 0) end), 0)
  into parent_cash_committed
  from public.petty_cash_requests
  where allocation_id = parent_allocation.id
    and id <> new.id
    and status not in ('draft', 'rejected', 'cancelled', 'leader_changes_requested', 'department_changes_requested');

  if new.allocation_id = parent_allocation.id then
    parent_cash_committed := parent_cash_committed + new_amount;
  end if;

  if child_allocated + parent_cash_committed > parent_allocation.amount then
    raise exception 'The task budget has already been distributed to subtasks or committed to task-level petty cash' using errcode = '22023';
  end if;

  return new;
end;
$$;

drop trigger if exists petty_cash_allocation_capacity_guard on public.petty_cash_requests;
create trigger petty_cash_allocation_capacity_guard
before insert or update of allocation_id, requested_amount, approved_amount, actual_spent, status
on public.petty_cash_requests
for each row execute function public.guard_petty_cash_allocation_capacity();

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
  subtask public.subtasks;
  parent_allocation public.work_budget_allocations;
  created_allocation_id uuid;
  fiscal_budget_id uuid;
begin
  if caller is null then raise exception 'Not authenticated' using errcode = '42501'; end if;
  if p_amount <= 0 or nullif(btrim(p_reason), '') is null then
    raise exception 'Enter a positive amount and purpose' using errcode = '22023';
  end if;

  select * into task from public.tasks where id = p_task_id;
  if not found then raise exception 'Task not found' using errcode = 'P0002'; end if;
  select * into subtask from public.subtasks where id = p_subtask_id and task_id = task.id;
  if not found then raise exception 'Subtask does not belong to this task' using errcode = '22023'; end if;
  if caller is distinct from coalesce(task.recommendation_lead_id, task.assigned_to) then
    raise exception 'Only the Task Leader can distribute task funding to a subtask' using errcode = '42501';
  end if;

  select * into parent_allocation
  from public.work_budget_allocations
  where task_id = task.id and subtask_id is null and status = 'approved'
  for update;
  if not found then raise exception 'The task has no approved proposal allocation' using errcode = '22023'; end if;

  insert into public.work_budget_allocations(
    commitment_id, task_id, subtask_id, parent_allocation_line_id, amount,
    status, reason, requested_by, decided_by, decision_reason, requested_at, decided_at
  ) values (
    parent_allocation.commitment_id, task.id, p_subtask_id, p_parent_allocation_line_id, p_amount,
    'approved', btrim(p_reason), caller, caller,
    'Distributed by the Task Leader from the approved task budget', now(), now()
  ) returning id into created_allocation_id;

  if p_parent_allocation_line_id is not null then
    insert into public.work_budget_allocation_lines(
      allocation_id, draft_task_key, expense_class, category, particular,
      quantity, unit, unit_cost, amount, fund_source, position
    )
    select created_allocation_id, draft_task_key, expense_class, category, particular,
      1, 'allocation', p_amount, p_amount, fund_source, 0
    from public.work_budget_allocation_lines
    where id = p_parent_allocation_line_id;
  end if;

  select fiscal_budget_id into fiscal_budget_id
  from public.budget_commitments where id = parent_allocation.commitment_id;
  insert into public.budget_ledger_entries(
    fiscal_budget_id, org_id, commitment_id, allocation_id, entry_type, amount, description, actor_id, metadata
  ) values (
    fiscal_budget_id, task.org_id, parent_allocation.commitment_id, created_allocation_id,
    'allocation_approved', p_amount, 'Task Leader distributed approved task funding to a subtask', caller,
    jsonb_build_object('taskId', task.id, 'subtaskId', subtask.id)
  );

  insert into public.notifications(
    user_id, type, title, message, task_id, task_title, actor_id, actor_name, financial_record_id, financial_record_type
  )
  select distinct contributor_id, 'subtask_budget_assigned', 'Subtask budget assigned',
    to_char(p_amount, 'FM999G999G999G990D00') || ' was assigned to your subtask "' || subtask.title || '".',
    task.id, task.title, caller, coalesce(profile.full_name, ''), created_allocation_id, 'work_budget_allocation'
  from unnest(coalesce(subtask.assigned_to_ids, '{}'::uuid[])) contributor_id
  left join public.profiles profile on profile.id = caller
  where contributor_id <> caller;

  return created_allocation_id;
end;
$$;

-- Earlier versions placed leader-created subtask distributions in a second
-- department approval queue. The parent task budget is already approved, so
-- promote those safe, existing distributions to the same direct delegation rule.
update public.work_budget_allocations allocation
set status = 'approved',
    decided_by = coalesce(decided_by, requested_by),
    decision_reason = coalesce(decision_reason, 'Distributed by the Task Leader from the approved task budget'),
    decided_at = coalesce(decided_at, now())
where allocation.subtask_id is not null
  and allocation.status = 'pending'
  and exists (
    select 1 from public.tasks task
    where task.id = allocation.task_id
      and allocation.requested_by = coalesce(task.recommendation_lead_id, task.assigned_to)
  );

notify pgrst, 'reload schema';

commit;
