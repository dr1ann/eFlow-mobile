-- A person may leave a task team only after every subtask assigned to them is
-- completed. This protects task membership changes made from any UI or RPC.

create or replace function public.guard_active_subtask_team_member_removal()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  removed_ids uuid[];
  blocked_member_name text;
  blocked_subtask_title text;
begin
  if new.team_member_ids is not distinct from old.team_member_ids then
    return new;
  end if;

  select coalesce(array_agg(member_id), '{}'::uuid[])
  into removed_ids
  from unnest(coalesce(old.team_member_ids, '{}'::uuid[])) member_id
  where not (member_id = any(coalesce(new.team_member_ids, '{}'::uuid[])));

  if cardinality(removed_ids) = 0 then
    return new;
  end if;

  select coalesce(profile.full_name, 'A task member'), subtask.title
  into blocked_member_name, blocked_subtask_title
  from public.subtasks subtask
  cross join lateral unnest(coalesce(subtask.assigned_to_ids, '{}'::uuid[])) assignee_id
  left join public.profiles profile on profile.id = assignee_id
  where subtask.task_id = old.id
    and coalesce(subtask.status, 'todo') <> 'completed'
    and not coalesce(subtask.is_completed, false)
    and assignee_id = any(removed_ids)
  order by subtask.position, subtask.created_at
  limit 1;

  if blocked_subtask_title is not null then
    raise exception '% cannot be removed while assigned to unfinished subtask "%"',
      blocked_member_name,
      blocked_subtask_title
      using errcode = '22023';
  end if;

  return new;
end;
$$;

drop trigger if exists tasks_guard_active_subtask_team_member_removal on public.tasks;
create trigger tasks_guard_active_subtask_team_member_removal
before update of team_member_ids on public.tasks
for each row execute function public.guard_active_subtask_team_member_removal();

revoke all on function public.guard_active_subtask_team_member_removal() from public, anon, authenticated;

