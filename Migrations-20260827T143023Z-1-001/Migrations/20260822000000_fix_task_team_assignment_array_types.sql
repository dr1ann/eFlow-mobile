-- `assign_task_with_details` accepts JSONB so PostgREST callers can pass
-- JavaScript arrays. `tasks.team_member_ids` and `team_member_names` are
-- PostgreSQL uuid[] and text[] columns, respectively. The original function
-- attempted to COALESCE those unlike types directly, which breaks every team
-- update before the task row can be saved.

create or replace function public.assign_task_with_details(
  p_task_id uuid,
  p_assignee uuid,
  p_assignee_name text default null,
  p_team_id text default null,
  p_team_name text default null,
  p_team_member_ids jsonb default null,
  p_team_member_names jsonb default null,
  p_reviewer uuid default null,
  p_backup_reviewer uuid default null,
  p_set_reviewers boolean default false
)
returns public.tasks
language plpgsql
security definer
set search_path = public
as $$
declare
  caller uuid := auth.uid();
  caller_name text;
  before_task public.tasks;
  assigned_task public.tasks;
  resolved_reviewer uuid;
  resolved_backup uuid;
begin
  if caller is null then
    raise exception 'Not authenticated' using errcode = '42501';
  end if;
  if p_team_member_ids is not null
     and jsonb_typeof(p_team_member_ids) <> 'array' then
    raise exception 'Team member ids must be an array' using errcode = '22023';
  end if;
  if p_team_member_names is not null
     and jsonb_typeof(p_team_member_names) <> 'array' then
    raise exception 'Team member names must be an array' using errcode = '22023';
  end if;

  select full_name into caller_name from public.profiles where id = caller;
  select * into before_task
  from public.tasks
  where id = p_task_id and deleted_at is null
  for update;
  if not found then raise exception 'Task not found'; end if;
  if not public.can_manage_task(p_task_id, caller) then
    raise exception 'Not allowed to assign this task' using errcode = '42501';
  end if;

  resolved_reviewer := case
    when p_set_reviewers then p_reviewer
    else before_task.reviewer_id
  end;
  if resolved_reviewer = p_assignee then
    resolved_reviewer := case
      when before_task.created_by is distinct from p_assignee then before_task.created_by
      else null
    end;
  end if;
  if resolved_reviewer is null then
    select o.head_user_id into resolved_reviewer
    from public.organizations o
    where o.id = before_task.org_id
      and o.head_user_id is distinct from p_assignee;
  end if;

  resolved_backup := case
    when p_set_reviewers then p_backup_reviewer
    else before_task.backup_reviewer_id
  end;
  if resolved_backup = p_assignee or resolved_backup = resolved_reviewer then
    resolved_backup := null;
  end if;

  update public.tasks
  set
    team_id = coalesce(p_team_id, team_id),
    team_name = coalesce(p_team_name, team_name),
    team_member_ids = case
      when p_team_member_ids is null then team_member_ids
      else array(
        select nullif(trim(member.value), '')::uuid
        from jsonb_array_elements_text(p_team_member_ids) as member(value)
        where nullif(trim(member.value), '') is not null
      )
    end,
    team_member_names = case
      when p_team_member_names is null then team_member_names
      else array(
        select member.value
        from jsonb_array_elements_text(p_team_member_names) as member(value)
      )
    end,
    reviewer_id = resolved_reviewer,
    backup_reviewer_id = resolved_backup
  where id = p_task_id;

  if before_task.assigned_to is distinct from p_assignee
     or (before_task.status = 'pending_assignment' and p_assignee is not null) then
    select public.assign_task(
      p_task_id,
      p_assignee,
      p_assignee_name
    ) into assigned_task;
  else
    select * into assigned_task from public.tasks where id = p_task_id;
  end if;

  if before_task.assigned_to is not null
     and before_task.assigned_to is distinct from p_assignee
     and before_task.assigned_to <> caller then
    insert into public.notifications (
      user_id, type, title, message, task_id, task_title,
      actor_id, actor_name, status_from, status_to, reason
    ) values (
      before_task.assigned_to,
      'reassignment',
      'Task reassigned',
      '"' || before_task.title || '" was reassigned to another owner.',
      p_task_id,
      before_task.title,
      caller,
      coalesce(caller_name, 'Manager'),
      before_task.status,
      assigned_task.status,
      ''
    );
  end if;

  return assigned_task;
end;
$$;

revoke all on function public.assign_task_with_details(
  uuid, uuid, text, text, text, jsonb, jsonb, uuid, uuid, boolean
) from public, anon;
grant execute on function public.assign_task_with_details(
  uuid, uuid, text, text, text, jsonb, jsonb, uuid, uuid, boolean
) to authenticated;
