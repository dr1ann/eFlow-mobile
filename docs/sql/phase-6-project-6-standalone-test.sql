-- Small Phase 6 standalone test for existing Project 6.
-- Run this WHOLE file in the NON-PRODUCTION Supabase SQL Editor as postgres.
-- Creates ONE in-progress parent and exactly THREE sequential, untouched subtasks.
-- Lead: gabzcah@gmail.com; contributor: kurt@gmail.com; Head: bplo.head@gmail.com.
-- Reruns preserve this fixture, including manual progress and mode changes.
-- Writes use authenticated actors and existing RPCs/RLS. No deadlines or files.
-- Source checked: 46e6f520c5e4dcd71c4e6ae40610518079b71b7c.
-- Not executed against your Supabase project by Codex.

begin;
set local timezone = 'Asia/Singapore';

do $seed$
declare
  v_project public.projects%rowtype;
  v_lead public.profiles%rowtype;
  v_member public.profiles%rowtype;
  v_head public.profiles%rowtype;
  v_task public.tasks%rowtype;
  v_marker constant text := 'phase6-project6-standalone-test-v1';
  v_existing integer;
  v_lookup text;
  v_previous_sub text := current_setting('request.jwt.claim.sub', true);
  v_previous_claims text := current_setting('request.jwt.claims', true);
  v_previous_role text := current_setting('role');
begin
  perform pg_advisory_xact_lock(hashtextextended(v_marker, 0));
  begin
    v_lookup := 'project named Project 6';
    select * into strict v_project from public.projects
    where lower(btrim(title)) = 'project 6' for update;
    v_lookup := 'active Task Lead gabzcah@gmail.com';
    select * into strict v_lead from public.profiles
    where lower(btrim(email)) = 'gabzcah@gmail.com' and is_active;
    v_lookup := 'active contributor kurt@gmail.com';
    select * into strict v_member from public.profiles
    where lower(btrim(email)) = 'kurt@gmail.com' and is_active;
    v_lookup := 'active Head bplo.head@gmail.com';
    select * into strict v_head from public.profiles
    where lower(btrim(email)) = 'bplo.head@gmail.com' and is_active;
  exception
    when no_data_found then raise exception 'Missing %. Nothing created.', v_lookup;
    when too_many_rows then raise exception 'Duplicate %. Nothing created.', v_lookup;
  end;

  select count(*) into v_existing from public.tasks where v_marker = any(tags);
  if v_existing = 1 then
    select * into strict v_task from public.tasks where v_marker = any(tags);
    if v_task.linked_project_id is distinct from v_project.id
       or (select count(*) from public.subtasks where task_id = v_task.id) <> 3 then
      raise exception 'Existing fixture has changed project or subtask count. Inspect it; nothing changed.';
    end if;
    raise notice 'Fixture already exists. All manual changes preserved.';
    return;
  elsif v_existing <> 0 then
    raise exception 'Duplicate fixture parents found. Nothing changed.';
  end if;

  if v_project.org_id is null or v_project.archived_at is not null
     or v_project.status is null
     or v_project.status not in ('planning', 'active', 'in_progress') then
    raise exception 'Project 6 must have an organization and be planning/active.';
  end if;
  if v_lead.id = v_member.id or v_lead.id = v_head.id or v_member.id = v_head.id then
    raise exception 'Task Lead, contributor, and Head must be different people.';
  end if;

  perform set_config('request.jwt.claim.sub', v_head.id::text, true);
  perform set_config('request.jwt.claims', jsonb_build_object(
    'sub', v_head.id, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
  select * into strict v_task from public.create_task_with_details(jsonb_build_object(
    'title', '[P6 TEST] Three-step standalone practice',
    'description', 'Leave steps 1 and 2 incomplete. Toggle step 3 before starting it.',
    'org_id', v_project.org_id,
    'linked_project_id', v_project.id,
    'project_id', v_project.id::text,
    'project_title', v_project.title,
    'assigned_to', v_lead.id,
    'assignee_name', coalesce(nullif(btrim(v_lead.full_name), ''), v_lead.email),
    'team_member_ids', jsonb_build_array(v_lead.id, v_member.id),
    'team_member_names', jsonb_build_array(
      coalesce(nullif(btrim(v_lead.full_name), ''), v_lead.email),
      coalesce(nullif(btrim(v_member.full_name), ''), v_member.email)),
    'reviewer_id', v_head.id,
    'priority', 'medium',
    'tags', jsonb_build_array(v_marker)
  ));
  if v_task.assigned_to is distinct from v_lead.id
     or v_task.reviewer_id is distinct from v_head.id
     or v_task.linked_project_id is distinct from v_project.id
     or v_task.status is distinct from 'todo'
     or not coalesce(v_member.id = any(v_task.team_member_ids), false) then
    raise exception 'Server returned unexpected task relationships/state. Setup rolled back.';
  end if;

  perform set_config('request.jwt.claim.sub', v_lead.id::text, true);
  perform set_config('request.jwt.claims', jsonb_build_object(
    'sub', v_lead.id, 'role', 'authenticated')::text, true);
  perform public.transition_task_status(v_task.id, 'in_progress');
  insert into public.subtasks (
    task_id, title, source, position, created_by, assigned_to, assigned_to_ids,
    is_standalone, status, percent_complete, is_completed
  )
  select v_task.id, step.title, 'manual', step.position, v_lead.id,
    v_member.id, array[v_member.id], false, 'todo', 0, false
  from (values
    (0, '[P6 STEP 1] Prepare checklist'),
    (1, '[P6 STEP 2] Check checklist'),
    (2, '[P6 STEP 3] Prepare independent reference sheet')
  ) as step(position, title);

  execute 'reset role';
  perform set_config('role', v_previous_role, true);
  perform set_config('request.jwt.claim.sub', coalesce(v_previous_sub, ''), true);
  perform set_config('request.jwt.claims', coalesce(v_previous_claims, ''), true);
  raise notice 'Created 1 parent and 3 sequential subtasks. Leave steps 1 and 2 incomplete.';
end;
$seed$;
commit;

-- Administrator inventory only; verify behavior again using actual app logins.
select t.title as task, t.id as task_id, t.status as task_status,
  s.position + 1 as step, s.title as subtask, s.id as subtask_id,
  s.is_standalone, s.status, s.percent_complete
from public.tasks t join public.subtasks s on s.task_id = t.id
where 'phase6-project6-standalone-test-v1' = any(t.tags)
order by s.position, s.id;
