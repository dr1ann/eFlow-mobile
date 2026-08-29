-- Explicit review routing and immutable review-attempt history.
-- This migration intentionally keeps the existing task status vocabulary and
-- public RPC signatures while closing the self-approval and evidence-mixing gaps.

create extension if not exists pgcrypto;

alter table public.tasks
  add column if not exists reviewer_id uuid references public.profiles(id) on delete set null,
  add column if not exists backup_reviewer_id uuid references public.profiles(id) on delete set null;

create index if not exists tasks_reviewer_idx on public.tasks(reviewer_id);
create index if not exists tasks_backup_reviewer_idx on public.tasks(backup_reviewer_id);

update public.tasks t
set reviewer_id = coalesce(
  case when t.recommendation_lead_id is distinct from t.assigned_to
    then t.recommendation_lead_id end,
  case when t.created_by is distinct from t.assigned_to
    then t.created_by end,
  (
    select o.head_user_id
    from public.organizations o
    where o.id = t.org_id
      and o.head_user_id is distinct from t.assigned_to
  )
)
where t.reviewer_id is null;

create table if not exists public.task_submissions (
  id uuid primary key default gen_random_uuid(),
  task_id uuid not null references public.tasks(id) on delete cascade,
  version int not null,
  submitter_id uuid not null references public.profiles(id) on delete restrict,
  submitter_name text not null default 'User',
  note text not null check (btrim(note) <> ''),
  status text not null default 'pending'
    check (status in ('pending', 'approved', 'changes_requested')),
  decided_by uuid references public.profiles(id) on delete set null,
  decided_by_name text,
  decision_feedback text,
  decided_at timestamptz,
  submitted_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  unique (task_id, version)
);

create index if not exists task_submissions_task_idx
  on public.task_submissions(task_id, version desc);

alter table public.task_attachments
  add column if not exists submission_id uuid
    references public.task_submissions(id) on delete cascade;

create index if not exists task_attachments_submission_idx
  on public.task_attachments(submission_id);

-- Preserve the currently materialized submission as version 1 for existing tasks.
insert into public.task_submissions (
  id,
  task_id,
  version,
  submitter_id,
  submitter_name,
  note,
  submitted_at
)
select
  case
    when coalesce(t.latest_submission ->> 'id', '') ~
      '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$'
      then (t.latest_submission ->> 'id')::uuid
    else gen_random_uuid()
  end,
  t.id,
  1,
  (t.latest_submission ->> 'submitterId')::uuid,
  coalesce(nullif(t.latest_submission ->> 'submitterName', ''), 'User'),
  t.latest_submission ->> 'note',
  case
    when coalesce(t.latest_submission ->> 'submittedAt', '') ~ '^\d+(\.\d+)?$'
      then to_timestamp((t.latest_submission ->> 'submittedAt')::numeric / 1000)
    else now()
  end
from public.tasks t
where t.latest_submission is not null
  and coalesce(btrim(t.latest_submission ->> 'note'), '') <> ''
  and coalesce(t.latest_submission ->> 'submitterId', '') ~
    '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$'
on conflict (task_id, version) do nothing;

update public.tasks t
set latest_submission = t.latest_submission || jsonb_build_object(
  'id', s.id::text,
  'version', s.version
)
from public.task_submissions s
where s.task_id = t.id
  and s.version = 1
  and not (t.latest_submission ? 'id');

create or replace function public.validate_task_reviewers()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  reviewer_active boolean;
begin
  if new.reviewer_id is not null then
    if new.reviewer_id = new.assigned_to then
      raise exception 'The assignee cannot review their own task'
        using errcode = '22023';
    end if;
    select is_active into reviewer_active
    from public.profiles where id = new.reviewer_id;
    if not coalesce(reviewer_active, false) then
      raise exception 'Primary reviewer must be an active profile'
        using errcode = '22023';
    end if;
  end if;

  if new.backup_reviewer_id is not null then
    if new.backup_reviewer_id = new.assigned_to
       or new.backup_reviewer_id = new.reviewer_id then
      raise exception 'Backup reviewer must differ from assignee and primary reviewer'
        using errcode = '22023';
    end if;
    select is_active into reviewer_active
    from public.profiles where id = new.backup_reviewer_id;
    if not coalesce(reviewer_active, false) then
      raise exception 'Backup reviewer must be an active profile'
        using errcode = '22023';
    end if;
  end if;

  return new;
end;
$$;

drop trigger if exists tasks_validate_reviewers on public.tasks;
create trigger tasks_validate_reviewers
before insert or update of assigned_to, reviewer_id, backup_reviewer_id
on public.tasks
for each row execute function public.validate_task_reviewers();

-- A direct status RPC must not bypass the dedicated review decision function.
create or replace function public.guard_task_review_decision()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if old.status = 'for_review'
     and new.status in ('completed', 'changes_requested')
     and coalesce(current_setting('eflow.review_decision_authorized', true), 'off') <> 'on' then
    raise exception 'Review decisions must use decide_task_review'
      using errcode = '42501';
  end if;
  return new;
end;
$$;

drop trigger if exists tasks_guard_review_decision on public.tasks;
create trigger tasks_guard_review_decision
before update of status on public.tasks
for each row execute function public.guard_task_review_decision();

create or replace function public.can_see_task(
  target_task uuid,
  caller_id uuid
)
returns boolean
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  row_task public.tasks;
  caller_role text;
begin
  if caller_id is null then return false; end if;
  caller_role := public.auth_role(caller_id);
  if caller_role = 'super_admin' then return true; end if;

  select * into row_task
  from public.tasks
  where id = target_task and deleted_at is null;
  if not found then return false; end if;

  return (
    row_task.assigned_to = caller_id
    or row_task.created_by = caller_id
    or row_task.recommendation_lead_id = caller_id
    or row_task.reviewer_id = caller_id
    or row_task.backup_reviewer_id = caller_id
    or coalesce(to_jsonb(row_task.team_member_ids), '[]'::jsonb) ? caller_id::text
    or (
      row_task.linked_project_id is not null
      and public.is_project_member(row_task.linked_project_id, caller_id)
    )
    or (
      caller_role in ('dept_head', 'department_head')
      and public.org_in_my_subtree(row_task.org_id, caller_id)
    )
  );
end;
$$;

alter table public.task_submissions enable row level security;

drop policy if exists task_submissions_read on public.task_submissions;
create policy task_submissions_read on public.task_submissions
  for select to authenticated
  using (public.can_see_task(task_id, auth.uid()));

-- Storage is uploaded first; this RPC records the submission, its attachment
-- rows, status/history/audit, and reviewer notification in one transaction.
-- Some early eFlow deployments created this exact signature with a different
-- return type. PostgreSQL cannot change a function return type through
-- CREATE OR REPLACE, so remove only the legacy signature before installing the
-- current contract. No task or submission rows are affected.
drop function if exists public.submit_task_for_review(uuid, jsonb);

create or replace function public.submit_task_for_review(
  p_task_id uuid,
  p_submission jsonb
)
returns public.tasks
language plpgsql
security definer
set search_path = public
as $$
declare
  caller uuid := auth.uid();
  caller_name text;
  completion_note text;
  submission_id uuid;
  submission_version int;
  attachment jsonb;
  normalized_submission jsonb;
  t public.tasks;
  resolved_reviewer uuid;
begin
  if caller is null then
    raise exception 'Not authenticated' using errcode = '42501';
  end if;

  completion_note := nullif(btrim(p_submission ->> 'note'), '');
  if completion_note is null then
    raise exception 'Completion note is required' using errcode = '22023';
  end if;
  if p_submission ? 'attachments'
     and jsonb_typeof(p_submission -> 'attachments') <> 'array' then
    raise exception 'Submission attachments must be an array' using errcode = '22023';
  end if;

  select full_name into caller_name
  from public.profiles where id = caller;

  select * into t
  from public.tasks
  where id = p_task_id and deleted_at is null
  for update;
  if not found then raise exception 'Task not found'; end if;
  if t.archived_at is not null or t.status <> 'in_progress' then
    raise exception 'Only in-progress work can be submitted' using errcode = '22023';
  end if;
  if not (t.assigned_to = caller or t.recommendation_lead_id = caller) then
    raise exception 'Only the assignee or task lead may submit this work'
      using errcode = '42501';
  end if;

  resolved_reviewer := case
    when t.reviewer_id is not null
      and t.reviewer_id <> caller
      and t.reviewer_id is distinct from t.assigned_to then t.reviewer_id
    when t.backup_reviewer_id is not null
      and t.backup_reviewer_id <> caller
      and t.backup_reviewer_id is distinct from t.assigned_to then t.backup_reviewer_id
    when t.created_by is not null
      and t.created_by <> caller
      and t.created_by is distinct from t.assigned_to then t.created_by
    else null
  end;
  if resolved_reviewer is null then
    select o.head_user_id into resolved_reviewer
    from public.organizations o
    where o.id = t.org_id
      and o.head_user_id is not null
      and o.head_user_id <> caller
      and o.head_user_id is distinct from t.assigned_to;
  end if;
  if resolved_reviewer is null then
    raise exception 'Assign a reviewer who is not the submitter before submitting'
      using errcode = '22023';
  end if;

  submission_id := case
    when coalesce(p_submission ->> 'id', '') ~
      '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$'
      then (p_submission ->> 'id')::uuid
    else gen_random_uuid()
  end;
  select coalesce(max(version), 0) + 1 into submission_version
  from public.task_submissions where task_id = p_task_id;

  insert into public.task_submissions (
    id, task_id, version, submitter_id, submitter_name, note
  ) values (
    submission_id,
    p_task_id,
    submission_version,
    caller,
    coalesce(caller_name, 'User'),
    completion_note
  );

  for attachment in
    select value from jsonb_array_elements(
      coalesce(p_submission -> 'attachments', '[]'::jsonb)
    )
  loop
    insert into public.task_attachments (
      task_id,
      submission_id,
      uploaded_by,
      uploader_name,
      file_name,
      file_path,
      file_size,
      mime_type
    ) values (
      p_task_id,
      submission_id,
      caller,
      coalesce(caller_name, 'User'),
      coalesce(attachment ->> 'fileName', 'Attachment'),
      attachment ->> 'filePath',
      case
        when coalesce(attachment ->> 'fileSize', '') ~ '^\d+$'
          then (attachment ->> 'fileSize')::bigint
        else 0
      end,
      coalesce(attachment ->> 'mimeType', '')
    );
  end loop;

  normalized_submission := jsonb_build_object(
    'id', submission_id::text,
    'version', submission_version,
    'note', completion_note,
    'submitterId', caller::text,
    'submitterName', coalesce(caller_name, 'User'),
    'submittedAt', floor(extract(epoch from clock_timestamp()) * 1000)::bigint,
    'attachments', coalesce(p_submission -> 'attachments', '[]'::jsonb)
  );

  perform set_config('eflow.allow_status_write', 'on', true);
  update public.tasks
  set
    reviewer_id = resolved_reviewer,
    latest_submission = normalized_submission,
    feedback = null,
    percent_complete = 100,
    status = 'for_review',
    last_activity_at = now()
  where id = p_task_id
  returning * into t;
  perform set_config('eflow.allow_status_write', 'off', true);

  insert into public.task_status_history (
    task_id, from_status, to_status, actor_id, actor_name, note
  ) values (
    p_task_id, 'in_progress', 'for_review', caller,
    coalesce(caller_name, 'User'), completion_note
  );

  insert into public.task_activities (
    task_id, type, content, actor_id, actor_name
  ) values (
    p_task_id, 'for_review', completion_note, caller,
    coalesce(caller_name, 'User')
  );

  insert into public.audit_events (
    actor_id, actor_name, entity_type, entity_id, action,
    reason, before_data, after_data, org_id
  ) values (
    caller, coalesce(caller_name, 'User'), 'task', p_task_id::text,
    'task.transition.for_review', completion_note,
    jsonb_build_object('status', 'in_progress'),
    jsonb_build_object(
      'status', 'for_review',
      'submissionId', submission_id,
      'submissionVersion', submission_version,
      'reviewerId', resolved_reviewer
    ),
    t.org_id
  );

  if resolved_reviewer <> caller then
    insert into public.notifications (
      user_id, type, title, message, task_id, task_title,
      actor_id, actor_name, status_from, status_to, reason
    ) values (
      resolved_reviewer, 'approval_needed', 'Task ready for review',
      coalesce(caller_name, 'Someone') || ' submitted "' || t.title || '" for review.',
      p_task_id, t.title, caller, coalesce(caller_name, 'User'),
      'in_progress', 'for_review', completion_note
    );
  end if;

  return t;
end;
$$;

-- Keep this migration compatible with databases that still have the original
-- review-decision RPC return type. This is the exact function signature only;
-- CASCADE is intentionally not used.
drop function if exists public.decide_task_review(uuid, boolean, text, text);

create or replace function public.decide_task_review(
  p_task_id uuid,
  p_approve boolean,
  p_feedback text default null,
  p_audit_hash text default null
)
returns public.tasks
language plpgsql
security definer
set search_path = public
as $$
declare
  caller uuid := auth.uid();
  caller_role text;
  caller_name text;
  t public.tasks;
  submission public.task_submissions;
  next_status text;
  decision_hash text;
begin
  if caller is null then
    raise exception 'Not authenticated' using errcode = '42501';
  end if;
  if not p_approve and coalesce(btrim(p_feedback), '') = '' then
    raise exception 'Feedback is required when requesting changes'
      using errcode = '22023';
  end if;

  select role::text, full_name into caller_role, caller_name
  from public.profiles where id = caller;

  select * into t
  from public.tasks
  where id = p_task_id and deleted_at is null
  for update;
  if not found then raise exception 'Task not found'; end if;
  if t.status <> 'for_review' then
    raise exception 'Task is not awaiting review' using errcode = '22023';
  end if;

  select * into submission
  from public.task_submissions
  where task_id = p_task_id
  order by version desc
  limit 1
  for update;
  if not found then
    raise exception 'No review submission exists' using errcode = '22023';
  end if;
  if submission.submitter_id = caller then
    raise exception 'You cannot review your own submission' using errcode = '42501';
  end if;
  if not (
    caller_role = 'super_admin'
    or t.reviewer_id = caller
    or t.backup_reviewer_id = caller
  ) then
    raise exception 'Only the assigned reviewer may decide this submission'
      using errcode = '42501';
  end if;

  next_status := case when p_approve then 'completed' else 'changes_requested' end;
  decision_hash := case when p_approve then encode(
    digest(
      p_task_id::text || ':' || submission.id::text || ':' || caller::text || ':' ||
      clock_timestamp()::text,
      'sha256'
    ),
    'hex'
  ) else null end;

  perform set_config('eflow.allow_status_write', 'on', true);
  perform set_config('eflow.review_decision_authorized', 'on', true);
  update public.tasks
  set
    status = next_status,
    percent_complete = case when p_approve then 100 else 99 end,
    feedback = nullif(btrim(p_feedback), ''),
    rejection_note = case
      when p_approve then rejection_note
      else nullif(btrim(p_feedback), '')
    end,
    rejected_at = case when p_approve then rejected_at else now() end,
    audit_hash = coalesce(decision_hash, audit_hash),
    last_activity_at = now()
  where id = p_task_id
  returning * into t;
  perform set_config('eflow.review_decision_authorized', 'off', true);
  perform set_config('eflow.allow_status_write', 'off', true);

  update public.task_submissions
  set
    status = case when p_approve then 'approved' else 'changes_requested' end,
    decided_by = caller,
    decided_by_name = coalesce(caller_name, 'Reviewer'),
    decision_feedback = nullif(btrim(p_feedback), ''),
    decided_at = now()
  where id = submission.id;

  insert into public.task_status_history (
    task_id, from_status, to_status, actor_id, actor_name, note
  ) values (
    p_task_id, 'for_review', next_status, caller,
    coalesce(caller_name, 'Reviewer'), nullif(btrim(p_feedback), '')
  );

  insert into public.task_activities (
    task_id, type, content, actor_id, actor_name
  ) values (
    p_task_id, next_status,
    coalesce(nullif(btrim(p_feedback), ''), 'Review approved'),
    caller, coalesce(caller_name, 'Reviewer')
  );

  insert into public.audit_events (
    actor_id, actor_name, entity_type, entity_id, action,
    reason, before_data, after_data, org_id
  ) values (
    caller, coalesce(caller_name, 'Reviewer'), 'task', p_task_id::text,
    'task.transition.' || next_status, nullif(btrim(p_feedback), ''),
    jsonb_build_object('status', 'for_review', 'submissionId', submission.id),
    jsonb_build_object('status', next_status, 'auditHash', decision_hash),
    t.org_id
  );

  if t.assigned_to is not null and t.assigned_to <> caller then
    insert into public.notifications (
      user_id, type, title, message, task_id, task_title,
      actor_id, actor_name, status_from, status_to, reason
    ) values (
      t.assigned_to,
      case when p_approve then 'completed' else 'status_change' end,
      case when p_approve then 'Task approved' else 'Changes requested' end,
      case
        when p_approve then '"' || t.title || '" was approved.'
        else 'Changes were requested for "' || t.title || '".'
      end,
      p_task_id, t.title, caller, coalesce(caller_name, 'Reviewer'),
      'for_review', next_status, coalesce(nullif(btrim(p_feedback), ''), '')
    );
  end if;

  return t;
end;
$$;

revoke all on table public.task_submissions from anon;
grant select on table public.task_submissions to authenticated;

revoke all on function public.submit_task_for_review(uuid, jsonb)
  from public, anon;
revoke all on function public.decide_task_review(uuid, boolean, text, text)
  from public, anon;
grant execute on function public.submit_task_for_review(uuid, jsonb)
  to authenticated;
grant execute on function public.decide_task_review(uuid, boolean, text, text)
  to authenticated;

-- Keep assignment identity, team membership, reviewer routing, history, and
-- notifications inside one database transaction.
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
    team_member_ids = coalesce(p_team_member_ids, team_member_ids),
    team_member_names = coalesce(p_team_member_names, team_member_names),
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

create or replace function public.set_task_archived(
  p_task_id uuid,
  p_archived boolean
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
  changed_task public.tasks;
begin
  if caller is null then
    raise exception 'Not authenticated' using errcode = '42501';
  end if;
  select full_name into caller_name from public.profiles where id = caller;
  select * into before_task from public.tasks
  where id = p_task_id and deleted_at is null
  for update;
  if not found then raise exception 'Task not found'; end if;
  if not public.can_manage_task(p_task_id, caller) then
    raise exception 'Not allowed to archive this task' using errcode = '42501';
  end if;

  update public.tasks
  set archived_at = case when p_archived then now() else null end,
      last_activity_at = now()
  where id = p_task_id
  returning * into changed_task;

  insert into public.audit_events (
    actor_id, actor_name, entity_type, entity_id, action,
    before_data, after_data, org_id
  ) values (
    caller, coalesce(caller_name, 'Manager'), 'task', p_task_id::text,
    case when p_archived then 'task.archived' else 'task.unarchived' end,
    jsonb_build_object('archived', before_task.archived_at is not null),
    jsonb_build_object('archived', p_archived),
    before_task.org_id
  );

  return changed_task;
end;
$$;

create or replace function public.soft_delete_task(p_task_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  caller uuid := auth.uid();
  caller_name text;
  t public.tasks;
begin
  if caller is null then
    raise exception 'Not authenticated' using errcode = '42501';
  end if;
  select full_name into caller_name from public.profiles where id = caller;
  select * into t from public.tasks
  where id = p_task_id and deleted_at is null
  for update;
  if not found then raise exception 'Task not found'; end if;
  if not public.can_manage_task(p_task_id, caller) then
    raise exception 'Not allowed to delete this task' using errcode = '42501';
  end if;

  update public.tasks set deleted_at = now(), last_activity_at = now()
  where id = p_task_id;

  insert into public.audit_events (
    actor_id, actor_name, entity_type, entity_id, action,
    before_data, after_data, org_id
  ) values (
    caller, coalesce(caller_name, 'Manager'), 'task', p_task_id::text,
    'task.deleted', to_jsonb(t), jsonb_build_object('deleted', true), t.org_id
  );
end;
$$;

revoke all on function public.assign_task_with_details(
  uuid, uuid, text, text, text, jsonb, jsonb, uuid, uuid, boolean
) from public, anon;
revoke all on function public.set_task_archived(uuid, boolean) from public, anon;
revoke all on function public.soft_delete_task(uuid) from public, anon;
grant execute on function public.assign_task_with_details(
  uuid, uuid, text, text, text, jsonb, jsonb, uuid, uuid, boolean
) to authenticated;
grant execute on function public.set_task_archived(uuid, boolean) to authenticated;
grant execute on function public.soft_delete_task(uuid) to authenticated;

-- Subtask coordination belongs to the task owner/lead/manager. Individual
-- assignees may only check or uncheck a subtask delegated to them.
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
  select public.can_manage_task(target_task, caller_id)
    or exists (
      select 1 from public.tasks t
      where t.id = target_task
        and t.deleted_at is null
        and t.assigned_to = caller_id
    );
$$;

create or replace function public.guard_subtask_contributor_update()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  caller uuid := auth.uid();
begin
  if public.can_manage_subtasks(old.task_id, caller) then
    return new;
  end if;

  if not (
    old.assigned_to = caller
    or coalesce(to_jsonb(old.assigned_to_ids), '[]'::jsonb) ? caller::text
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

  new.completed_by := case when new.is_completed then caller else null end;
  new.completed_at := case when new.is_completed then now() else null end;
  return new;
end;
$$;

drop trigger if exists subtasks_guard_contributor_update on public.subtasks;
create trigger subtasks_guard_contributor_update
before update on public.subtasks
for each row execute function public.guard_subtask_contributor_update();

drop policy if exists subtasks_insert on public.subtasks;
drop policy if exists subtasks_update on public.subtasks;
drop policy if exists subtasks_delete on public.subtasks;

create policy subtasks_insert on public.subtasks
  for insert to authenticated
  with check (
    public.can_manage_subtasks(task_id, auth.uid())
    and created_by = auth.uid()
  );

create policy subtasks_update on public.subtasks
  for update to authenticated
  using (
    public.can_manage_subtasks(task_id, auth.uid())
    or assigned_to = auth.uid()
    or coalesce(to_jsonb(assigned_to_ids), '[]'::jsonb) ? auth.uid()::text
  )
  with check (
    public.can_manage_subtasks(task_id, auth.uid())
    or assigned_to = auth.uid()
    or coalesce(to_jsonb(assigned_to_ids), '[]'::jsonb) ? auth.uid()::text
  );

create policy subtasks_delete on public.subtasks
  for delete to authenticated
  using (public.can_manage_subtasks(task_id, auth.uid()));
