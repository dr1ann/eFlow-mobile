-- Phase 5 manual-test setup for existing Project 5.
-- Run this WHOLE file in your NON-PRODUCTION Supabase SQL Editor as postgres.
-- Contributor: kurt@gmail.com; Task Lead: gabzcah@gmail.com;
-- Department Head / parent reviewer: bplo.head@gmail.com.
-- Creates 44 tasks and 43 subtasks, plus normal RPC history/notifications.
-- Project 5 must be active/planning and its target date must be unset or at
-- least 8 days from today. Dates below use Asia/Singapore, matching the tester.
-- A successful rerun preserves this dataset, including subsequent manual work.
-- Existing work, accounts, roles, project settings, and evidence stay intact.
-- All workflow writes run as authenticated actors through existing RPCs/RLS.
-- Source checked at web main 46e6f520c5e4dcd71c4e6ae40610518079b71b7c.
-- Not executed against your Supabase project by Codex.
-- Read phase-5-project-5-test.md for the fixture map and remaining manual steps.

begin;
set local timezone = 'Asia/Singapore';

do $seed$
declare
  v_project public.projects%rowtype;
  v_lead public.profiles%rowtype;
  v_member public.profiles%rowtype;
  v_head public.profiles%rowtype;
  v_task public.tasks%rowtype;
  v_subtask public.subtasks%rowtype;
  v_marker constant text := 'phase5-project5-discovery-test-v1';
  v_lookup text;
  v_existing integer;
  v_i integer;
  v_j integer;
  v_label text;
  v_due date;
  v_assignee uuid;
  v_recommended_lead uuid;
  v_project_id uuid;
  v_team_ids jsonb;
  v_team_names jsonb;
  v_probe_task uuid;
  v_probe_subtask uuid;
  v_probe_task_visible boolean;
  v_probe_subtask_visible boolean;
  v_previous_sub text := current_setting('request.jwt.claim.sub', true);
  v_previous_claims text := current_setting('request.jwt.claims', true);
  v_previous_role text := current_setting('role');
begin
  -- Serialize concurrent runs of this exact fixture before checking its marker.
  perform pg_advisory_xact_lock(hashtextextended(v_marker, 0));

  begin
    v_lookup := 'project named Project 5';
    select * into strict v_project from public.projects
    where lower(btrim(title)) = 'project 5'
    for update;

    v_lookup := 'active profile for gabzcah@gmail.com';
    select * into strict v_lead from public.profiles
    where lower(btrim(email)) = 'gabzcah@gmail.com' and is_active;

    v_lookup := 'active profile for kurt@gmail.com';
    select * into strict v_member from public.profiles
    where lower(btrim(email)) = 'kurt@gmail.com' and is_active;

    v_lookup := 'active profile for bplo.head@gmail.com';
    select * into strict v_head from public.profiles
    where lower(btrim(email)) = 'bplo.head@gmail.com' and is_active;
  exception
    when no_data_found then
      raise exception 'Missing %. Nothing was created.', v_lookup;
    when too_many_rows then
      raise exception 'More than one matching %. Nothing was created.', v_lookup;
  end;

  select count(*) into v_existing from public.tasks
  where v_marker = any(tags);
  if v_existing = 44 then
    raise notice 'Phase 5 fixtures already exist. Existing dates, decisions, and evidence were preserved.';
    return;
  elsif v_existing <> 0 then
    raise exception 'Found % existing Phase 5 tasks, expected 44. Inspect the partial/edited dataset; nothing was changed.', v_existing;
  end if;

  if v_project.org_id is null
     or v_project.archived_at is not null
     or v_project.status not in ('planning', 'active', 'in_progress') then
    raise exception 'Project 5 needs an organization and a planning/active status. Nothing was created.';
  end if;
  if v_project.target_date is not null and v_project.target_date < current_date + 8 then
    raise exception 'Project 5 target date is %. These boundary tests need % or later (or no target date). Nothing was created.',
      v_project.target_date, current_date + 8;
  end if;
  if v_lead.id = v_member.id or v_lead.id = v_head.id or v_member.id = v_head.id then
    raise exception 'Contributor, Task Lead, and reviewer must be different people. Nothing was created.';
  end if;

  for v_i in 1..44 loop
    v_label := case
      when v_i <= 31 then 'Pagination ' || lpad(v_i::text, 2, '0') || ' - overdue'
      when v_i = 32 then 'Due today'
      when v_i = 33 then 'Due in exactly 7 days'
      when v_i = 34 then 'Due in exactly 8 days'
      when v_i = 35 then 'No deadline'
      when v_i = 36 then 'In progress and subtask review practice'
      when v_i = 37 then 'Waiting for assignment'
      when v_i = 38 then 'Gabriel leads - stale Kurt recommendation'
      when v_i = 39 then 'Kurt assigned ONLY to subtask'
      when v_i = 40 then 'Parent awaiting Head review'
      when v_i = 41 then 'Parent changes requested'
      when v_i = 42 then 'Parent completed with two submission versions'
      when v_i = 43 then 'Cancelled parent - History filter'
      when v_i = 44 then 'Unlinked task - no project action'
    end;
    v_due := case
      when v_i <= 31 then current_date - 1
      when v_i = 32 then current_date
      when v_i = 33 then current_date + 7
      when v_i = 34 then current_date + 8
      when v_i = 35 then null
      else current_date + 2
    end;
    v_assignee := case when v_i = 37 then null else v_lead.id end;
    v_recommended_lead := case
      when v_i = 37 then v_lead.id
      when v_i = 38 then v_member.id
      else null
    end;
    v_project_id := case when v_i = 44 then null else v_project.id end;
    v_team_ids := case when v_i = 39 then jsonb_build_array(v_lead.id)
      else jsonb_build_array(v_lead.id, v_member.id) end;
    v_team_names := case when v_i = 39 then jsonb_build_array(
        coalesce(nullif(btrim(v_lead.full_name), ''), v_lead.email))
      else jsonb_build_array(
        coalesce(nullif(btrim(v_lead.full_name), ''), v_lead.email),
        coalesce(nullif(btrim(v_member.full_name), ''), v_member.email)) end;

    perform set_config('request.jwt.claim.sub', v_head.id::text, true);
    perform set_config('request.jwt.claims', jsonb_build_object(
      'sub', v_head.id, 'role', 'authenticated')::text, true);
    execute 'set local role authenticated';

    select * into strict v_task from public.create_task_with_details(jsonb_build_object(
      'title', '[P5 TEST ' || lpad(v_i::text, 2, '0') || '] ' || v_label,
      'description', 'Synthetic Phase 5 test: ' || v_label ||
        '. Contributor: Kurt. Task Lead: Gabriel. Parent reviewer: Department Head. Seed date: ' || current_date::text || '.',
      'org_id', v_project.org_id,
      'linked_project_id', v_project_id,
      -- Deliberately use a legacy non-UUID value on #38. Routing must use
      -- linked_project_id, while #44 has no project relationship at all.
      'project_id', case when v_i = 38 then 'p5-legacy-hierarchy-slug'
        else v_project_id::text end,
      'project_title', case when v_project_id is null then null else v_project.title end,
      'priority', case when v_i <= 31 then 'high' else 'medium' end,
      'assigned_to', v_assignee,
      'assignee_name', case when v_assignee is null then ''
        else coalesce(nullif(btrim(v_lead.full_name), ''), v_lead.email) end,
      'recommendation_lead_id', v_recommended_lead,
      'team_name', 'Phase 5 test team',
      'team_member_ids', v_team_ids,
      'team_member_names', v_team_names,
      'reviewer_id', v_head.id,
      'deadline', coalesce(v_due::text, ''),
      'due_date', coalesce(v_due::text, ''),
      'tags', jsonb_build_array(v_marker, 'p5-case-' || lpad(v_i::text, 2, '0')),
      'acceptance_criteria', jsonb_build_array('Verify the named Phase 5 discovery scenario.'),
      'definition_of_done', 'Record the observed mobile result for this synthetic test.',
      'budget_impact', 0,
      'percent_complete', 0
    ));

    if v_task.assigned_to is distinct from v_assignee
       or v_task.recommendation_lead_id is distinct from v_recommended_lead
       or v_task.reviewer_id is distinct from v_head.id
       or v_task.linked_project_id is distinct from v_project_id
       or v_task.status is distinct from (case when v_i = 37 then 'pending_assignment' else 'todo' end)
       or (v_i = 39 and v_member.id = any(v_task.team_member_ids)) then
      raise exception 'Case %: server assignment/project/status differs from the fixture. Entire setup rolled back.', v_i;
    end if;

    -- Progress/submission state is produced through the same RPCs as mobile.
    perform set_config('request.jwt.claim.sub', v_lead.id::text, true);
    perform set_config('request.jwt.claims', jsonb_build_object(
      'sub', v_lead.id, 'role', 'authenticated')::text, true);
    if v_i in (36, 40, 41, 42) then
      perform public.transition_task_status(v_task.id, 'in_progress');
    end if;

    -- No subtasks on pending-assignment/review/completed/cancelled parents.
    if v_i <= 36 or v_i in (38, 39, 44) then
      if public.resolve_subtask_reviewer(v_task, v_member.id) is distinct from v_lead.id then
        raise exception 'Case %: Gabriel is not the resolved subtask reviewer. Entire setup rolled back.', v_i;
      end if;
      insert into public.subtasks (
        task_id, title, source, position, created_by,
        assigned_to, assigned_to_ids, due_date, is_standalone,
        status, percent_complete, is_completed
      ) values (
        v_task.id, '[P5 SUB ' || lpad(v_i::text, 2, '0') || '] ' || v_label,
        'manual', 0, v_lead.id,
        -- #31 also tests an array-only assignment, with no scalar assignee.
        case when v_i = 31 then null else v_member.id end,
        array[v_member.id], v_due, true, 'todo', 0, false
      ) returning * into strict v_subtask;

      if v_i = 39 then
        v_probe_task := v_task.id;
        v_probe_subtask := v_subtask.id;
      end if;

      if v_i = 36 then
        -- Independent practice items can be submitted in any order with REAL
        -- evidence from the app. SQL cannot create a genuine Storage upload.
        for v_j in 1..4 loop
          insert into public.subtasks (
            task_id, title, source, position, created_by,
            assigned_to, assigned_to_ids, due_date, is_standalone,
            status, percent_complete, is_completed
          ) values (
            v_task.id,
            '[P5 REVIEW ' || v_j || '] ' || case v_j
              when 1 then 'Submit and leave awaiting review'
              when 2 then 'Submit then request changes'
              when 3 then 'Submit then approve'
              when 4 then 'Request changes then resubmit version 2'
            end,
            'manual', v_j, v_lead.id, v_member.id, array[v_member.id],
            v_due, true, 'todo', 0, false
          );
        end loop;

        perform set_config('request.jwt.claim.sub', v_member.id::text, true);
        perform set_config('request.jwt.claims', jsonb_build_object(
          'sub', v_member.id, 'role', 'authenticated')::text, true);
        perform public.save_subtask_progress(
          p_subtask_id := v_subtask.id, p_percent_complete := 25,
          p_note := 'Synthetic Phase 5 progress entry: verify history from My Subtasks.',
          p_next_step := 'Open the four named review-practice subtasks.'
        );
      end if;
    end if;

    if v_i in (40, 41, 42) then
      -- Parent attachments are optional. These parents have NO subtasks, so
      -- note-only submissions are valid and make real versioned history.
      perform public.submit_task_for_review(v_task.id, jsonb_build_object(
        'id', gen_random_uuid(),
        'note', 'Synthetic Phase 5 parent submission, version 1. No files or subtasks required for this discovery fixture.',
        'attachments', jsonb_build_array()
      ));
      if v_i in (41, 42) then
        perform set_config('request.jwt.claim.sub', v_head.id::text, true);
        perform set_config('request.jwt.claims', jsonb_build_object(
          'sub', v_head.id, 'role', 'authenticated')::text, true);
        perform public.decide_task_review(v_task.id, false,
          'Synthetic test feedback: include the deadline-check result in your completion note.');
      end if;
      if v_i = 42 then
        perform set_config('request.jwt.claim.sub', v_lead.id::text, true);
        perform set_config('request.jwt.claims', jsonb_build_object(
          'sub', v_lead.id, 'role', 'authenticated')::text, true);
        perform public.transition_task_status(v_task.id, 'in_progress');
        perform public.submit_task_for_review(v_task.id, jsonb_build_object(
          'id', gen_random_uuid(),
          'note', 'Synthetic Phase 5 version 2: the deadline-check result is now included.',
          'attachments', jsonb_build_array()
        ));
        perform set_config('request.jwt.claim.sub', v_head.id::text, true);
        perform set_config('request.jwt.claims', jsonb_build_object(
          'sub', v_head.id, 'role', 'authenticated')::text, true);
        perform public.decide_task_review(v_task.id, true,
          'Synthetic Phase 5 approval: verify both submission versions in history.');
      end if;
    elsif v_i = 43 then
      perform set_config('request.jwt.claim.sub', v_head.id::text, true);
      perform set_config('request.jwt.claims', jsonb_build_object(
        'sub', v_head.id, 'role', 'authenticated')::text, true);
      perform public.cancel_task(v_task.id,
        'Synthetic Phase 5 cancellation for the History filter.');
    end if;
  end loop;

  -- Database-role probe only: it does not establish mobile login acceptance.
  -- Do not add Kurt to the parent team if this reports false; record the result.
  perform set_config('request.jwt.claim.sub', v_member.id::text, true);
  perform set_config('request.jwt.claims', jsonb_build_object(
    'sub', v_member.id, 'role', 'authenticated')::text, true);
  select exists (select 1 from public.tasks where id = v_probe_task)
    into v_probe_task_visible;
  select exists (select 1 from public.subtasks where id = v_probe_subtask)
    into v_probe_subtask_visible;
  raise notice 'Case 39, authenticated Kurt: parent readable=%, assigned subtask readable=%. Confirm again in mobile.',
    v_probe_task_visible, v_probe_subtask_visible;

  execute 'reset role';
  perform set_config('role', v_previous_role, true);
  perform set_config('request.jwt.claim.sub', coalesce(v_previous_sub, ''), true);
  perform set_config('request.jwt.claims', coalesce(v_previous_claims, ''), true);
  raise notice 'Created 44 tasks and 43 subtasks for Phase 5, with normal RPC history and notifications. Seed date: %.', current_date;
end;
$seed$;

commit;

-- Fixture inventory. This administrator result is NOT an RLS acceptance test.
select
  t.title as task,
  t.id as task_id,
  t.status as task_status,
  nullif(t.due_date, '') as task_due_date,
  p.title as project,
  s.title as subtask,
  s.id as subtask_id,
  s.status as subtask_status,
  s.due_date as subtask_due_date
from public.tasks t
left join public.projects p on p.id = t.linked_project_id
left join public.subtasks s on s.task_id = t.id
where 'phase5-project5-discovery-test-v1' = any(t.tags)
order by t.title, s.position, s.id;
