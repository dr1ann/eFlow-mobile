-- Creates a task through one authenticated, explicitly-authorized database
-- operation. This avoids browser INSERT/RETURNING RLS failures while retaining
-- all existing task validation and lifecycle triggers.

create or replace function public.create_task_with_details(p_payload jsonb)
returns public.tasks
language plpgsql
security definer
set search_path = public
as $$
declare
  caller uuid := auth.uid();
  caller_profile public.profiles;
  target_org uuid;
  selected_assignee uuid := nullif(p_payload ->> 'assigned_to', '')::uuid;
  initial_status text;
  task_priority text := coalesce(nullif(trim(p_payload ->> 'priority'), ''), 'medium');
  created_task public.tasks;
begin
  if caller is null then
    raise exception 'Authentication is required to create a task'
      using errcode = '42501';
  end if;

  select * into caller_profile
  from public.profiles
  where id = caller and is_active;
  if not found then
    raise exception 'An active eFlow profile is required to create a task'
      using errcode = '42501';
  end if;

  if nullif(trim(p_payload ->> 'title'), '') is null then
    raise exception 'Task title is required'
      using errcode = '22023';
  end if;
  if task_priority not in ('low', 'medium', 'high') then
    raise exception 'Invalid task priority'
      using errcode = '22023';
  end if;

  target_org := coalesce(
    nullif(p_payload ->> 'org_id', '')::uuid,
    caller_profile.org_id
  );
  if not public.can_create_scoped_work(target_org, caller) then
    raise exception 'You cannot create tasks in this organization'
      using errcode = '42501';
  end if;

  if selected_assignee is not null and not exists (
    select 1 from public.profiles
    where id = selected_assignee and is_active
  ) then
    raise exception 'Task assignee must be an active eFlow user'
      using errcode = '22023';
  end if;

  initial_status := case
    when selected_assignee is null then 'pending_assignment'
    else 'todo'
  end;

  insert into public.tasks (
    title,
    description,
    status,
    priority,
    assigned_to,
    assignee_name,
    department,
    org_id,
    team_id,
    team_name,
    team_member_ids,
    team_member_names,
    deadline,
    due_date,
    tags,
    recommended_employee_ids,
    recommendation_reasoning,
    recommendation_source,
    recommendation_lead_id,
    reviewer_id,
    backup_reviewer_id,
    acceptance_criteria,
    definition_of_done,
    dependency_ids,
    burnout_warning,
    proposal_id,
    proposal_title,
    program_id,
    program_title,
    project_id,
    project_title,
    activity_id,
    activity_title,
    activity_schedule,
    hierarchy_path,
    import_batch_id,
    barangay,
    estimated_hours,
    budget_impact,
    linked_project_id,
    milestone_id,
    percent_complete,
    created_by
  ) values (
    trim(p_payload ->> 'title'),
    nullif(p_payload ->> 'description', ''),
    initial_status,
    task_priority,
    selected_assignee,
    coalesce(p_payload ->> 'assignee_name', ''),
    coalesce(p_payload ->> 'department', ''),
    target_org,
    coalesce(p_payload ->> 'team_id', ''),
    coalesce(p_payload ->> 'team_name', ''),
    array(
      select value::uuid
      from jsonb_array_elements_text(coalesce(p_payload -> 'team_member_ids', '[]'::jsonb))
    ),
    array(
      select value
      from jsonb_array_elements_text(coalesce(p_payload -> 'team_member_names', '[]'::jsonb))
    ),
    coalesce(p_payload ->> 'deadline', ''),
    coalesce(p_payload ->> 'due_date', p_payload ->> 'deadline', ''),
    array(
      select value
      from jsonb_array_elements_text(coalesce(p_payload -> 'tags', '[]'::jsonb))
    ),
    array(
      select value::uuid
      from jsonb_array_elements_text(coalesce(p_payload -> 'recommended_employee_ids', '[]'::jsonb))
    ),
    nullif(p_payload ->> 'recommendation_reasoning', ''),
    nullif(p_payload ->> 'recommendation_source', ''),
    nullif(p_payload ->> 'recommendation_lead_id', '')::uuid,
    nullif(p_payload ->> 'reviewer_id', '')::uuid,
    nullif(p_payload ->> 'backup_reviewer_id', '')::uuid,
    coalesce(p_payload -> 'acceptance_criteria', '[]'::jsonb),
    nullif(p_payload ->> 'definition_of_done', ''),
    coalesce(
      array(
        select value::uuid
        from jsonb_array_elements_text(coalesce(p_payload -> 'dependency_ids', '[]'::jsonb))
      ),
      '{}'::uuid[]
    ),
    coalesce((p_payload ->> 'burnout_warning')::boolean, false),
    nullif(p_payload ->> 'proposal_id', ''),
    nullif(p_payload ->> 'proposal_title', ''),
    nullif(p_payload ->> 'program_id', ''),
    nullif(p_payload ->> 'program_title', ''),
    nullif(p_payload ->> 'project_id', ''),
    nullif(p_payload ->> 'project_title', ''),
    nullif(p_payload ->> 'activity_id', ''),
    nullif(p_payload ->> 'activity_title', ''),
    nullif(p_payload ->> 'activity_schedule', ''),
    nullif(p_payload ->> 'hierarchy_path', ''),
    nullif(p_payload ->> 'import_batch_id', ''),
    nullif(p_payload ->> 'barangay', ''),
    coalesce((p_payload ->> 'estimated_hours')::numeric, 0),
    coalesce((p_payload ->> 'budget_impact')::numeric, 0),
    nullif(p_payload ->> 'linked_project_id', '')::uuid,
    nullif(p_payload ->> 'milestone_id', '')::uuid,
    coalesce((p_payload ->> 'percent_complete')::int, 0),
    caller
  )
  returning * into created_task;

  return created_task;
end;
$$;

revoke all on function public.create_task_with_details(jsonb) from public;
grant execute on function public.create_task_with_details(jsonb) to authenticated;
