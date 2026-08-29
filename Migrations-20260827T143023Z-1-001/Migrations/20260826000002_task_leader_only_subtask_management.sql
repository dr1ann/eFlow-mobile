-- Subtask structure is owned by the effective Task Leader. Organization roles,
-- task creators, project managers, and ordinary task members may retain their
-- broader task permissions without gaining the ability to create, reassign,
-- delete, reorder, reschedule, or change execution rules for subtasks.

begin;

create or replace function public.can_manage_subtasks(
  target_task uuid,
  caller_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.tasks task_row
    where task_row.id = target_task
      and task_row.deleted_at is null
      and coalesce(task_row.assigned_to, task_row.recommendation_lead_id) = caller_id
  );
$$;

notify pgrst, 'reload schema';

commit;
