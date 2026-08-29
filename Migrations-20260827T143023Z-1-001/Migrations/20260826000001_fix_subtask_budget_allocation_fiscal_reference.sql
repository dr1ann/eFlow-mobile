-- Qualify the fiscal-budget lookup used when a Task Leader distributes an
-- approved parent-task allocation. The prior function used fiscal_budget_id
-- as both a PL/pgSQL variable and a budget_commitments column, causing an
-- ambiguous-column error before the ledger entry could be written.

begin;

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
  target_fiscal_budget_id uuid;
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

  select commitment.fiscal_budget_id into target_fiscal_budget_id
  from public.budget_commitments commitment
  where commitment.id = parent_allocation.commitment_id;
  insert into public.budget_ledger_entries(
    fiscal_budget_id, org_id, commitment_id, allocation_id, entry_type, amount, description, actor_id, metadata
  ) values (
    target_fiscal_budget_id, task.org_id, parent_allocation.commitment_id, created_allocation_id,
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

notify pgrst, 'reload schema';

commit;
