-- Phase 4 manual-test setup: one task and one subtask in existing Project 5.
-- Run the whole script in your test Supabase SQL Editor as postgres.
-- Checked against web main 042e1a5b240cf667eb3dfa69d263897686de2a04.
-- Not executed against Supabase by Codex.
-- Existing accounts, roles, project settings, and evidence are not modified.
-- Request identity and database role changes below last only this transaction.

begin;

do $seed$
declare
  v_project public.projects%rowtype;
  v_lead public.profiles%rowtype;
  v_member public.profiles%rowtype;
  v_head public.profiles%rowtype;
  v_task public.tasks%rowtype;
  v_due date;
  v_lookup text;
  v_marker constant text := 'phase4-project5-evidence-test';
begin
  -- Exact, unique matches only. Do not silently pick the first project/user.
  begin
    v_lookup := 'project named Project 5';
    select * into strict v_project from public.projects
    where lower(btrim(title)) = 'project 5'
    for update;

    v_lookup := 'active profile for gabzcah@gmail.com';
    select * into strict v_lead from public.profiles
    where lower(btrim(email)) = 'gabzcah@gmail.com' and is_active;

    v_lookup := 'active profile for andres@gmail.com';
    select * into strict v_member from public.profiles
    where lower(btrim(email)) = 'andres@gmail.com' and is_active;

    v_lookup := 'active profile for bplo.head@gmail.com';
    select * into strict v_head from public.profiles
    where lower(btrim(email)) = 'bplo.head@gmail.com' and is_active;
  exception
    when no_data_found then
      raise exception 'Missing %. Nothing was created.', v_lookup;
    when too_many_rows then
      raise exception 'More than one matching %. Nothing was created.', v_lookup;
  end;

  -- A rerun preserves the original test, including any review history.
  if exists (
    select 1 from public.tasks
    where linked_project_id = v_project.id
      and v_marker = any(tags)
  ) then
    raise notice 'This Phase 4 test already exists. No records were changed.';
    return;
  end if;

  if v_project.org_id is null
     or v_project.archived_at is not null
     or v_project.status not in ('planning', 'active', 'in_progress') then
    raise exception 'Project 5 needs an organization and a planning/active status. Nothing was created.';
  end if;

  -- Keep the task/subtask deadline within the existing project target date.
  v_due := least(current_date + 7, coalesce(v_project.target_date, current_date + 7));

  -- Create through the same authorized RPC used by web, as the Head.
  perform set_config('request.jwt.claim.sub', v_head.id::text, true);
  perform set_config('request.jwt.claims', jsonb_build_object(
    'sub', v_head.id, 'role', 'authenticated'
  )::text, true);
  execute 'set local role authenticated';

  select * into v_task from public.create_task_with_details(jsonb_build_object(
    'title', '[P4 TEST] Evidence review and rework',
    'description', 'Andres submits evidence to Gabriel. Gabriel requests a correction, reviews version 2, then submits the parent task to the Department Head.',
    'org_id', v_project.org_id,
    'linked_project_id', v_project.id,
    'project_id', v_project.id::text,
    'project_title', v_project.title,
    'priority', 'medium',
    'assigned_to', v_lead.id,
    'assignee_name', coalesce(nullif(btrim(v_lead.full_name), ''), v_lead.email),
    'team_name', 'Phase 4 test team',
    'team_member_ids', jsonb_build_array(v_lead.id, v_member.id),
    'team_member_names', jsonb_build_array(
      coalesce(nullif(btrim(v_lead.full_name), ''), v_lead.email),
      coalesce(nullif(btrim(v_member.full_name), ''), v_member.email)
    ),
    'reviewer_id', v_head.id,
    'deadline', v_due::text,
    'due_date', v_due::text,
    'tags', jsonb_build_array(v_marker),
    'acceptance_criteria', jsonb_build_array(
      'Subtask evidence has been reviewed and approved.',
      'Completion note describes the finished work and correction.'
    ),
    'definition_of_done', 'Approved subtask, evidence-backed parent submission, and Department Head approval.',
    'budget_impact', 0,
    'percent_complete', 0
  ));

  if v_task.assigned_to is distinct from v_lead.id
     or v_task.reviewer_id is distinct from v_head.id then
    raise exception 'Server assignment/review routing differs from the requested accounts. Nothing was created.';
  end if;

  -- The web creates subtasks with an RLS-protected INSERT by the Task Lead.
  perform set_config('request.jwt.claim.sub', v_lead.id::text, true);
  perform set_config('request.jwt.claims', jsonb_build_object(
    'sub', v_lead.id, 'role', 'authenticated'
  )::text, true);

  if public.resolve_subtask_reviewer(v_task, v_member.id) is distinct from v_lead.id then
    raise exception 'The server did not resolve Gabriel as the subtask reviewer. Nothing was created.';
  end if;

  insert into public.subtasks (
    task_id, title, source, position, created_by,
    assigned_to, assigned_to_ids, due_date,
    status, percent_complete, is_completed
  ) values (
    v_task.id, '[P4 TEST] Prepare and correct evidence', 'manual', 0, v_lead.id,
    v_member.id, array[v_member.id], v_due,
    'todo', 0, false
  );

  -- The submission RPC will set subtask reviewer_id and create version history.
  raise notice 'Created 1 task and 1 subtask. Task ID: %', v_task.id;
end;
$seed$;

commit;

-- Results to identify the records on mobile/web, also shown on a safe rerun.
select
  p.title as project,
  t.id as task_id,
  t.title as task,
  t.status as task_status,
  s.id as subtask_id,
  s.title as subtask,
  s.status as subtask_status,
  t.due_date
from public.tasks t
join public.projects p on p.id = t.linked_project_id
left join public.subtasks s on s.task_id = t.id
where lower(btrim(p.title)) = 'project 5'
  and 'phase4-project5-evidence-test' = any(t.tags);
