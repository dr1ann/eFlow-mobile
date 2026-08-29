-- Ordered subtask execution with an explicit standalone escape hatch.
-- Regular subtasks wait for all earlier regular steps to be approved. A Team
-- Lead may mark untouched work standalone so it can run in parallel.

alter table public.subtasks
  add column if not exists is_standalone boolean not null default false;

comment on column public.subtasks.is_standalone is
  'When true, this subtask neither waits for nor blocks the ordered prerequisite chain.';

create or replace function public.guard_subtask_contributor_update()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  caller uuid := auth.uid();
  workflow_authorized boolean :=
    coalesce(current_setting('eflow.subtask_workflow_authorized', true), 'off') = 'on';
begin
  if workflow_authorized then
    return new;
  end if;

  if new.is_completed is distinct from old.is_completed
     or new.completed_by is distinct from old.completed_by
     or new.completed_at is distinct from old.completed_at
     or new.status is distinct from old.status
     or new.percent_complete is distinct from old.percent_complete
     or new.reviewer_id is distinct from old.reviewer_id
     or new.latest_submission_id is distinct from old.latest_submission_id then
    raise exception 'Open the subtask and submit evidence for review; direct check-off is disabled'
      using errcode = '42501';
  end if;

  if public.can_manage_subtasks(old.task_id, caller) then
    return new;
  end if;

  if not (
    old.assigned_to = caller
    or caller = any(coalesce(old.assigned_to_ids, '{}'::uuid[]))
  ) then
    raise exception 'This subtask is not assigned to you' using errcode = '42501';
  end if;

  if new.task_id is distinct from old.task_id
     or new.title is distinct from old.title
     or new.position is distinct from old.position
     or new.is_standalone is distinct from old.is_standalone
     or new.source is distinct from old.source
     or new.created_by is distinct from old.created_by
     or new.assigned_to is distinct from old.assigned_to
     or new.assigned_to_ids is distinct from old.assigned_to_ids then
    raise exception 'Only a task lead may edit, reassign, or change the execution rule of a subtask'
      using errcode = '42501';
  end if;

  return new;
end;
$$;

create or replace function public.guard_subtask_execution_dependencies()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  workflow_authorized boolean :=
    coalesce(current_setting('eflow.subtask_workflow_authorized', true), 'off') = 'on';
  blocking_title text;
  blocking_step integer;
begin
  -- Direct edits are handled by guard_subtask_contributor_update. Execution
  -- dependencies apply to the evidence/progress RPC workflow only.
  if not workflow_authorized then
    if new.is_standalone is distinct from old.is_standalone
       and (old.status <> 'todo' or old.percent_complete > 0) then
      raise exception 'Execution mode cannot change after subtask work has started'
        using errcode = '22023',
          hint = 'Reset or finish the existing work before changing between sequential and standalone.';
    end if;
    return new;
  end if;

  -- A reviewer must still be able to approve or request changes for evidence
  -- that was valid when submitted.
  if old.status = 'for_review' or new.is_standalone then
    return new;
  end if;

  select prerequisite.title, (
    select count(*)::integer
    from public.subtasks numbered
    where numbered.task_id = prerequisite.task_id
      and numbered.is_standalone = false
      and numbered.position <= prerequisite.position
  )
    into blocking_title, blocking_step
  from public.subtasks prerequisite
  where prerequisite.task_id = new.task_id
    and prerequisite.id <> new.id
    and prerequisite.position < new.position
    and prerequisite.is_standalone = false
    and prerequisite.is_completed = false
  order by prerequisite.position, prerequisite.created_at, prerequisite.id
  limit 1;

  if blocking_title is not null then
    raise exception 'Complete Step %: "%" before starting this subtask',
      blocking_step, blocking_title
      using errcode = '22023',
        detail = 'Ordered subtasks must be approved in sequence.',
        hint = 'Ask the Team Lead to mark this subtask Standalone only when it is genuinely independent.';
  end if;

  return new;
end;
$$;

drop trigger if exists subtasks_guard_execution_dependencies on public.subtasks;
create trigger subtasks_guard_execution_dependencies
before update of status, percent_complete, is_standalone on public.subtasks
for each row execute function public.guard_subtask_execution_dependencies();

revoke all on function public.guard_subtask_execution_dependencies()
  from public, anon, authenticated;

notify pgrst, 'reload schema';
