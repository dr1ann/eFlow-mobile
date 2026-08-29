-- Replaces direct subtask check-off with an evidence-backed workflow:
-- progress -> submission -> Team Leader decision -> completed roll-up.

alter table public.subtasks
  add column if not exists assigned_to_ids uuid[] not null default '{}'::uuid[],
  add column if not exists status text not null default 'todo',
  add column if not exists percent_complete int not null default 0,
  add column if not exists reviewer_id uuid references public.profiles(id) on delete set null;

do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'subtasks_status_check'
  ) then
    alter table public.subtasks add constraint subtasks_status_check
      check (status in ('todo', 'in_progress', 'for_review', 'changes_requested', 'completed'));
  end if;
  if not exists (
    select 1 from pg_constraint where conname = 'subtasks_percent_complete_check'
  ) then
    alter table public.subtasks add constraint subtasks_percent_complete_check
      check (percent_complete between 0 and 100);
  end if;
end;
$$;

-- Existing deployments already protect subtasks with mutation triggers, and
-- some older databases used different trigger names for the same guards.
-- Suspend every non-constraint trigger only for this compatibility backfill.
-- The DO statement is atomic, so an error restores the original trigger state.
do $$
begin
  execute 'alter table public.subtasks disable trigger user';

  update public.subtasks
  set
    status = case when is_completed then 'completed' else 'todo' end,
    percent_complete = case when is_completed then 100 else 0 end
  where status = 'todo' and percent_complete = 0;

  execute 'alter table public.subtasks enable trigger user';
end;
$$;

create table if not exists public.subtask_progress_updates (
  id uuid primary key default gen_random_uuid(),
  subtask_id uuid not null references public.subtasks(id) on delete cascade,
  task_id uuid not null references public.tasks(id) on delete cascade,
  author_id uuid not null references public.profiles(id) on delete restrict,
  author_name text not null default 'User',
  percent_complete int not null check (percent_complete between 0 and 99),
  blocker_category text,
  blocker text,
  next_step text,
  note text,
  attachment_path text,
  attachment_name text,
  created_at timestamptz not null default now()
);

create index if not exists subtask_progress_subtask_idx
  on public.subtask_progress_updates(subtask_id, created_at desc);

create table if not exists public.subtask_submissions (
  id uuid primary key default gen_random_uuid(),
  subtask_id uuid not null references public.subtasks(id) on delete cascade,
  task_id uuid not null references public.tasks(id) on delete cascade,
  version int not null,
  submitter_id uuid not null references public.profiles(id) on delete restrict,
  submitter_name text not null default 'User',
  reviewer_id uuid not null references public.profiles(id) on delete restrict,
  note text not null check (btrim(note) <> ''),
  status text not null default 'pending'
    check (status in ('pending', 'approved', 'changes_requested')),
  decided_by uuid references public.profiles(id) on delete set null,
  decided_by_name text,
  decision_feedback text,
  decided_at timestamptz,
  submitted_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  unique (subtask_id, version)
);

create index if not exists subtask_submissions_reviewer_idx
  on public.subtask_submissions(reviewer_id, status, submitted_at);
create index if not exists subtask_submissions_subtask_idx
  on public.subtask_submissions(subtask_id, version desc);

create table if not exists public.subtask_submission_attachments (
  id uuid primary key default gen_random_uuid(),
  submission_id uuid not null references public.subtask_submissions(id) on delete cascade,
  subtask_id uuid not null references public.subtasks(id) on delete cascade,
  task_id uuid not null references public.tasks(id) on delete cascade,
  uploaded_by uuid not null references public.profiles(id) on delete restrict,
  file_name text not null,
  file_path text not null,
  file_size bigint not null default 0,
  mime_type text not null default '',
  created_at timestamptz not null default now()
);

create index if not exists subtask_submission_attachments_submission_idx
  on public.subtask_submission_attachments(submission_id);

alter table public.subtasks
  add column if not exists latest_submission_id uuid
    references public.subtask_submissions(id) on delete set null;

alter table public.subtask_progress_updates enable row level security;
alter table public.subtask_submissions enable row level security;
alter table public.subtask_submission_attachments enable row level security;

drop policy if exists subtask_progress_read on public.subtask_progress_updates;
create policy subtask_progress_read on public.subtask_progress_updates
  for select to authenticated
  using (public.can_see_task(task_id, auth.uid()));

drop policy if exists subtask_submissions_read on public.subtask_submissions;
create policy subtask_submissions_read on public.subtask_submissions
  for select to authenticated
  using (public.can_see_task(task_id, auth.uid()));

drop policy if exists subtask_submission_attachments_read on public.subtask_submission_attachments;
create policy subtask_submission_attachments_read on public.subtask_submission_attachments
  for select to authenticated
  using (public.can_see_task(task_id, auth.uid()));

-- Workflow fields may only be changed by the RPCs below. Managers retain title,
-- order, and assignment controls; contributors cannot emulate approval by
-- directly updating is_completed.
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
     or new.source is distinct from old.source
     or new.created_by is distinct from old.created_by
     or new.assigned_to is distinct from old.assigned_to
     or new.assigned_to_ids is distinct from old.assigned_to_ids then
    raise exception 'Only a task lead may edit or reassign a subtask'
      using errcode = '42501';
  end if;

  return new;
end;
$$;

create or replace function public.resolve_subtask_reviewer(
  target_task public.tasks,
  submitter uuid
)
returns uuid
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  candidate uuid;
  candidate_active boolean;
begin
  foreach candidate in array array[
    target_task.recommendation_lead_id,
    target_task.reviewer_id,
    target_task.backup_reviewer_id,
    target_task.assigned_to,
    target_task.created_by
  ] loop
    if candidate is null or candidate = submitter then continue; end if;
    select is_active into candidate_active from public.profiles where id = candidate;
    if coalesce(candidate_active, false) then return candidate; end if;
  end loop;
  return null;
end;
$$;

create or replace function public.save_subtask_progress(
  p_subtask_id uuid,
  p_percent_complete int,
  p_blocker_category text default null,
  p_blocker text default null,
  p_next_step text default null,
  p_note text default null,
  p_attachment_path text default null,
  p_attachment_name text default null
)
returns public.subtasks
language plpgsql
security definer
set search_path = public
as $$
declare
  caller uuid := auth.uid();
  caller_name text;
  subtask_row public.subtasks;
  task_row public.tasks;
begin
  if caller is null then raise exception 'Not authenticated' using errcode = '42501'; end if;
  if p_percent_complete < 0 or p_percent_complete >= 100 then
    raise exception 'Use Submit for Leader Review when progress reaches 100%%'
      using errcode = '22023';
  end if;

  select * into subtask_row from public.subtasks where id = p_subtask_id for update;
  if not found then raise exception 'Subtask not found' using errcode = 'P0002'; end if;

  if not (
    subtask_row.assigned_to = caller
    or caller = any(coalesce(subtask_row.assigned_to_ids, '{}'::uuid[]))
  ) then
    raise exception 'This subtask is not assigned to you' using errcode = '42501';
  end if;

  if subtask_row.status in ('for_review', 'completed') then
    raise exception 'This subtask is locked while under review or completed'
      using errcode = '22023';
  end if;

  select * into task_row from public.tasks
  where id = subtask_row.task_id and deleted_at is null;
  if not found or task_row.status in ('for_review', 'completed', 'cancelled') then
    raise exception 'The parent task is not open for subtask progress'
      using errcode = '22023';
  end if;

  select full_name into caller_name from public.profiles where id = caller;

  perform set_config('eflow.subtask_workflow_authorized', 'on', true);
  update public.subtasks
  set
    percent_complete = p_percent_complete,
    status = case when p_percent_complete > 0 then 'in_progress' else 'todo' end,
    is_completed = false,
    completed_by = null,
    completed_at = null
  where id = p_subtask_id
  returning * into subtask_row;
  perform set_config('eflow.subtask_workflow_authorized', 'off', true);

  insert into public.subtask_progress_updates (
    subtask_id, task_id, author_id, author_name, percent_complete,
    blocker_category, blocker, next_step, note, attachment_path, attachment_name
  ) values (
    p_subtask_id, subtask_row.task_id, caller, coalesce(caller_name, 'User'),
    p_percent_complete, nullif(btrim(p_blocker_category), ''),
    nullif(btrim(p_blocker), ''), nullif(btrim(p_next_step), ''),
    nullif(btrim(p_note), ''), nullif(p_attachment_path, ''),
    nullif(p_attachment_name, '')
  );

  insert into public.task_activities (task_id, type, content, actor_id, actor_name)
  values (
    subtask_row.task_id, 'subtask_progress',
    'Updated "' || subtask_row.title || '" to ' || p_percent_complete || '%',
    caller, coalesce(caller_name, 'User')
  );

  return subtask_row;
end;
$$;

create or replace function public.submit_subtask_for_review(
  p_subtask_id uuid,
  p_submission jsonb
)
returns public.subtasks
language plpgsql
security definer
set search_path = public
as $$
declare
  caller uuid := auth.uid();
  caller_name text;
  subtask_row public.subtasks;
  task_row public.tasks;
  reviewer uuid;
  submission_id uuid;
  next_version int;
  previous_status text;
  note_text text;
  attachment jsonb;
  attachment_count int;
begin
  if caller is null then raise exception 'Not authenticated' using errcode = '42501'; end if;

  note_text := btrim(coalesce(p_submission ->> 'note', ''));
  if note_text = '' then raise exception 'Completion note is required' using errcode = '22023'; end if;
  attachment_count := jsonb_array_length(coalesce(p_submission -> 'attachments', '[]'::jsonb));
  if attachment_count = 0 then
    raise exception 'At least one evidence file is required for subtask review'
      using errcode = '22023';
  end if;

  select * into subtask_row from public.subtasks where id = p_subtask_id for update;
  if not found then raise exception 'Subtask not found' using errcode = 'P0002'; end if;

  if not (
    subtask_row.assigned_to = caller
    or caller = any(coalesce(subtask_row.assigned_to_ids, '{}'::uuid[]))
  ) then
    raise exception 'This subtask is not assigned to you' using errcode = '42501';
  end if;
  if subtask_row.status in ('for_review', 'completed') then
    raise exception 'This subtask is already under review or completed'
      using errcode = '22023';
  end if;
  previous_status := subtask_row.status;

  select * into task_row from public.tasks
  where id = subtask_row.task_id and deleted_at is null
  for update;
  if not found or task_row.status in ('for_review', 'completed', 'cancelled') then
    raise exception 'The parent task is not open for subtask submission'
      using errcode = '22023';
  end if;

  reviewer := public.resolve_subtask_reviewer(task_row, caller);
  if reviewer is null then
    raise exception 'No eligible Team Leader or task reviewer is available'
      using errcode = '22023';
  end if;

  select full_name into caller_name from public.profiles where id = caller;
  submission_id := coalesce(nullif(p_submission ->> 'id', '')::uuid, gen_random_uuid());
  select coalesce(max(version), 0) + 1 into next_version
  from public.subtask_submissions where subtask_id = p_subtask_id;

  insert into public.subtask_submissions (
    id, subtask_id, task_id, version, submitter_id, submitter_name,
    reviewer_id, note
  ) values (
    submission_id, p_subtask_id, subtask_row.task_id, next_version,
    caller, coalesce(caller_name, 'User'), reviewer, note_text
  );

  for attachment in select value from jsonb_array_elements(p_submission -> 'attachments') loop
    insert into public.subtask_submission_attachments (
      submission_id, subtask_id, task_id, uploaded_by,
      file_name, file_path, file_size, mime_type
    ) values (
      submission_id, p_subtask_id, subtask_row.task_id, caller,
      coalesce(nullif(attachment ->> 'fileName', ''), 'Evidence'),
      attachment ->> 'filePath',
      coalesce((attachment ->> 'fileSize')::bigint, 0),
      coalesce(attachment ->> 'mimeType', '')
    );
  end loop;

  perform set_config('eflow.subtask_workflow_authorized', 'on', true);
  update public.subtasks
  set
    status = 'for_review',
    percent_complete = 100,
    reviewer_id = reviewer,
    latest_submission_id = submission_id,
    is_completed = false,
    completed_by = null,
    completed_at = null
  where id = p_subtask_id
  returning * into subtask_row;
  perform set_config('eflow.subtask_workflow_authorized', 'off', true);

  insert into public.task_activities (task_id, type, content, actor_id, actor_name)
  values (
    subtask_row.task_id, 'subtask_for_review',
    coalesce(caller_name, 'User') || ' submitted subtask "' || subtask_row.title || '" for review',
    caller, coalesce(caller_name, 'User')
  );

  insert into public.audit_events (
    actor_id, actor_name, entity_type, entity_id, action, after_data, org_id
  ) values (
    caller, coalesce(caller_name, 'User'), 'subtask', p_subtask_id::text,
    'subtask.submitted',
    jsonb_build_object('submissionId', submission_id, 'version', next_version, 'reviewerId', reviewer),
    task_row.org_id
  );

  insert into public.notifications (
    user_id, type, title, message, task_id, task_title,
    actor_id, actor_name, status_from, status_to, reason
  ) values (
    reviewer, 'approval_needed', 'Subtask evidence ready for review',
    coalesce(caller_name, 'A team member') || ' submitted "' || subtask_row.title || '".',
    task_row.id, task_row.title, caller, coalesce(caller_name, 'User'),
    previous_status, 'for_review', note_text
  );

  return subtask_row;
end;
$$;

create or replace function public.decide_subtask_review(
  p_subtask_id uuid,
  p_approve boolean,
  p_feedback text default null
)
returns public.subtasks
language plpgsql
security definer
set search_path = public
as $$
declare
  caller uuid := auth.uid();
  caller_name text;
  caller_role text;
  subtask_row public.subtasks;
  task_row public.tasks;
  submission_row public.subtask_submissions;
  next_status text;
begin
  if caller is null then raise exception 'Not authenticated' using errcode = '42501'; end if;
  if not p_approve and btrim(coalesce(p_feedback, '')) = '' then
    raise exception 'Feedback is required when requesting changes'
      using errcode = '22023';
  end if;

  select role::text, full_name into caller_role, caller_name
  from public.profiles where id = caller;
  select * into subtask_row from public.subtasks where id = p_subtask_id for update;
  if not found then raise exception 'Subtask not found' using errcode = 'P0002'; end if;
  if subtask_row.status <> 'for_review' then
    raise exception 'Subtask is not awaiting review' using errcode = '22023';
  end if;

  select * into submission_row from public.subtask_submissions
  where id = subtask_row.latest_submission_id and status = 'pending'
  for update;
  if not found then raise exception 'Pending subtask submission not found' using errcode = '22023'; end if;
  if submission_row.submitter_id = caller then
    raise exception 'You cannot review your own subtask submission' using errcode = '42501';
  end if;
  if caller_role <> 'super_admin' and submission_row.reviewer_id <> caller then
    raise exception 'Only the assigned Team Leader may review this subtask'
      using errcode = '42501';
  end if;

  select * into task_row from public.tasks where id = subtask_row.task_id;
  next_status := case when p_approve then 'completed' else 'changes_requested' end;

  perform set_config('eflow.subtask_workflow_authorized', 'on', true);
  update public.subtasks
  set
    status = next_status,
    percent_complete = case when p_approve then 100 else 99 end,
    is_completed = p_approve,
    completed_by = case when p_approve then submission_row.submitter_id else null end,
    completed_at = case when p_approve then now() else null end
  where id = p_subtask_id
  returning * into subtask_row;
  perform set_config('eflow.subtask_workflow_authorized', 'off', true);

  update public.subtask_submissions
  set
    status = case when p_approve then 'approved' else 'changes_requested' end,
    decided_by = caller,
    decided_by_name = coalesce(caller_name, 'Team Leader'),
    decision_feedback = nullif(btrim(p_feedback), ''),
    decided_at = now()
  where id = submission_row.id;

  insert into public.task_activities (task_id, type, content, actor_id, actor_name)
  values (
    subtask_row.task_id, 'subtask_' || next_status,
    'Subtask "' || subtask_row.title || '" ' ||
      case when p_approve then 'was approved' else 'needs changes' end,
    caller, coalesce(caller_name, 'Team Leader')
  );

  insert into public.audit_events (
    actor_id, actor_name, entity_type, entity_id, action, reason,
    before_data, after_data, org_id
  ) values (
    caller, coalesce(caller_name, 'Team Leader'), 'subtask', p_subtask_id::text,
    'subtask.' || next_status, nullif(btrim(p_feedback), ''),
    jsonb_build_object('status', 'for_review', 'submissionId', submission_row.id),
    jsonb_build_object('status', next_status, 'completed', p_approve),
    task_row.org_id
  );

  insert into public.notifications (
    user_id, type, title, message, task_id, task_title,
    actor_id, actor_name, status_from, status_to, reason
  ) values (
    submission_row.submitter_id,
    case when p_approve then 'completed' else 'status_change' end,
    case when p_approve then 'Subtask approved' else 'Subtask changes requested' end,
    case
      when p_approve then 'Your evidence for "' || subtask_row.title || '" was approved.'
      else 'Changes were requested for "' || subtask_row.title || '".'
    end,
    task_row.id, task_row.title, caller, coalesce(caller_name, 'Team Leader'),
    'for_review', next_status, coalesce(nullif(btrim(p_feedback), ''), '')
  );

  return subtask_row;
end;
$$;

-- A parent task cannot enter department review until every subtask has passed
-- its Team Leader review.
create or replace function public.guard_task_subtask_readiness()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if new.status = 'for_review'
     and old.status is distinct from new.status
     and exists (
       select 1 from public.subtasks s
       where s.task_id = new.id and not s.is_completed
     ) then
    raise exception 'Every subtask must be approved before the parent task can be submitted'
      using errcode = '22023';
  end if;
  return new;
end;
$$;

drop trigger if exists tasks_guard_subtask_readiness on public.tasks;
create trigger tasks_guard_subtask_readiness
before update of status on public.tasks
for each row execute function public.guard_task_subtask_readiness();

revoke all on function public.resolve_subtask_reviewer(public.tasks, uuid) from public, anon, authenticated;
revoke all on function public.save_subtask_progress(uuid, int, text, text, text, text, text, text) from public, anon;
revoke all on function public.submit_subtask_for_review(uuid, jsonb) from public, anon;
revoke all on function public.decide_subtask_review(uuid, boolean, text) from public, anon;
grant execute on function public.save_subtask_progress(uuid, int, text, text, text, text, text, text) to authenticated;
grant execute on function public.submit_subtask_for_review(uuid, jsonb) to authenticated;
grant execute on function public.decide_subtask_review(uuid, boolean, text) to authenticated;

do $$
declare table_name text;
begin
  foreach table_name in array array[
    'subtask_progress_updates', 'subtask_submissions', 'subtask_submission_attachments'
  ] loop
    begin
      execute format('alter publication supabase_realtime add table public.%I', table_name);
    exception when duplicate_object then null; when undefined_object then null;
    end;
  end loop;
end;
$$;

notify pgrst, 'reload schema';
