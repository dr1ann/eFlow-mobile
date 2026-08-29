-- eFlow workflow consistency repair
--
-- Repairs the imported rows affected by createTask silently dropping
-- linked_project_id / milestone_id, makes subtask progress roll up to its
-- parent task, and closes role-scope gaps in task/project visibility and
-- lifecycle commands.

-- ─── 1. Safely reconnect legacy imported tasks to operational projects ──────
-- Only use an exact title + organization match when it resolves to exactly one
-- live project. Ambiguous rows remain unlinked for manual reconciliation.
with project_candidates as (
  select
    t.id as task_id,
    p.id as project_id,
    count(*) over (partition by t.id) as candidate_count
  from public.tasks t
  join public.projects p
    on lower(btrim(p.title)) = lower(btrim(t.project_title))
   and p.org_id is not distinct from t.org_id
   and p.archived_at is null
  where t.deleted_at is null
    and t.linked_project_id is null
    and t.org_id is not null
    and nullif(btrim(t.import_batch_id), '') is not null
    and nullif(btrim(t.project_title), '') is not null
),
linked as (
  update public.tasks t
     set linked_project_id = c.project_id,
         last_activity_at = coalesce(t.last_activity_at, now())
    from project_candidates c
   where t.id = c.task_id
     and c.candidate_count = 1
  returning t.id, t.org_id, t.linked_project_id
)
insert into public.audit_events (
  actor_name,
  entity_type,
  entity_id,
  action,
  reason,
  before_data,
  after_data,
  org_id
)
select
  'System migration',
  'task',
  id::text,
  'task.data_repaired.project_link',
  'Unique exact project title and organization match',
  jsonb_build_object('linked_project_id', null),
  jsonb_build_object('linked_project_id', linked_project_id),
  org_id
from linked;

-- Activity titles created the operational milestone records during import.
-- Apply the same unique-match rule inside the now-canonical project.
with milestone_candidates as (
  select
    t.id as task_id,
    m.id as milestone_id,
    count(*) over (partition by t.id) as candidate_count
  from public.tasks t
  join public.milestones m
    on m.project_id = t.linked_project_id
   and lower(btrim(m.title)) = lower(btrim(t.activity_title))
  where t.deleted_at is null
    and t.linked_project_id is not null
    and t.milestone_id is null
    and nullif(btrim(t.activity_title), '') is not null
),
linked as (
  update public.tasks t
     set milestone_id = c.milestone_id
    from milestone_candidates c
   where t.id = c.task_id
     and c.candidate_count = 1
  returning t.id, t.org_id, t.milestone_id
)
insert into public.audit_events (
  actor_name,
  entity_type,
  entity_id,
  action,
  reason,
  before_data,
  after_data,
  org_id
)
select
  'System migration',
  'task',
  id::text,
  'task.data_repaired.milestone_link',
  'Unique exact activity and project milestone match',
  jsonb_build_object('milestone_id', null),
  jsonb_build_object('milestone_id', milestone_id),
  org_id
from linked;

-- ─── 2. Normalize impossible 100% + To Do rows without self-approving ───────
-- These rows have no review submission, so move them to In Progress and leave
-- final completion to the normal submit/review flow.
do $$
declare
  repaired public.tasks;
begin
  perform set_config('eflow.allow_status_write', 'on', true);

  for repaired in
    update public.tasks
       set status = 'in_progress',
           last_activity_at = now()
     where deleted_at is null
       and archived_at is null
       and status = 'todo'
       and percent_complete = 100
       and latest_submission is null
    returning *
  loop
    insert into public.task_status_history (
      task_id,
      from_status,
      to_status,
      actor_name,
      note
    )
    values (
      repaired.id,
      'todo',
      'in_progress',
      'System migration',
      'Normalized 100% work that had remained in To Do; ready for review submission'
    );

    insert into public.task_activities (
      task_id,
      type,
      content,
      actor_name
    )
    values (
      repaired.id,
      'in_progress',
      '100% execution progress normalized from To Do; approval still required',
      'System migration'
    );

    insert into public.audit_events (
      actor_name,
      entity_type,
      entity_id,
      action,
      reason,
      before_data,
      after_data,
      org_id
    )
    values (
      'System migration',
      'task',
      repaired.id::text,
      'task.data_repaired.status',
      'A task with 100% progress cannot remain untouched To Do',
      jsonb_build_object('status', 'todo', 'percent_complete', 100),
      jsonb_build_object('status', 'in_progress', 'percent_complete', 100),
      repaired.org_id
    );
  end loop;

  perform set_config('eflow.allow_status_write', 'off', true);
end;
$$;

-- ─── 3. Role-aware visibility helpers ──────────────────────────────────────
-- Organization subtree access is managerial only. Employees see tasks they
-- participate in/lead and projects they own or explicitly belong to.
create or replace function public.can_see_project(
  target_project uuid,
  caller_id uuid
)
returns boolean
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  proj_org uuid;
  proj_owner uuid;
  caller_role text;
begin
  if caller_id is null then return false; end if;
  caller_role := public.auth_role(caller_id);
  if caller_role = 'super_admin' then return true; end if;

  select org_id, owner_id
    into proj_org, proj_owner
  from public.projects
  where id = target_project;
  if not found then return false; end if;

  return (
    proj_owner = caller_id
    or public.is_project_member(target_project, caller_id)
    or exists (
      select 1
      from public.tasks task_row
      where task_row.linked_project_id = target_project
        and task_row.deleted_at is null
        and (
          task_row.assigned_to = caller_id
          or task_row.recommendation_lead_id = caller_id
          or coalesce(to_jsonb(task_row.team_member_ids), '[]'::jsonb)
            ? caller_id::text
        )
    )
    or (
      caller_role in ('dept_head', 'department_head')
      and public.org_in_my_subtree(proj_org, caller_id)
    )
  );
end;
$$;

create or replace function public.can_manage_project(
  target_project uuid,
  caller_id uuid
)
returns boolean
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  proj_org uuid;
  proj_owner uuid;
  proj_creator uuid;
  caller_role text;
begin
  if caller_id is null then return false; end if;
  caller_role := public.auth_role(caller_id);
  if caller_role = 'super_admin' then return true; end if;

  select org_id, owner_id, created_by
    into proj_org, proj_owner, proj_creator
  from public.projects
  where id = target_project;
  if not found then return false; end if;

  return (
    proj_owner = caller_id
    or proj_creator = caller_id
    or (
      caller_role in ('dept_head', 'department_head')
      and public.org_in_my_subtree(proj_org, caller_id)
    )
  );
end;
$$;

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

  select *
    into row_task
  from public.tasks
  where id = target_task
    and deleted_at is null;
  if not found then return false; end if;

  return (
    row_task.assigned_to = caller_id
    or row_task.created_by = caller_id
    or row_task.recommendation_lead_id = caller_id
    or coalesce(to_jsonb(row_task.team_member_ids), '[]'::jsonb)
      ? caller_id::text
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

create or replace function public.can_contribute_task(
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

  select *
    into row_task
  from public.tasks
  where id = target_task
    and deleted_at is null;
  if not found then return false; end if;

  return (
    row_task.assigned_to = caller_id
    or row_task.recommendation_lead_id = caller_id
    or coalesce(to_jsonb(row_task.team_member_ids), '[]'::jsonb)
      ? caller_id::text
    or (
      caller_role in ('dept_head', 'department_head')
      and public.org_in_my_subtree(row_task.org_id, caller_id)
    )
  );
end;
$$;

create or replace function public.can_manage_task(
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

  select *
    into row_task
  from public.tasks
  where id = target_task
    and deleted_at is null;
  if not found then return false; end if;

  return (
    row_task.created_by = caller_id
    or row_task.recommendation_lead_id = caller_id
    or (
      caller_role in ('dept_head', 'department_head')
      and public.org_in_my_subtree(row_task.org_id, caller_id)
    )
  );
end;
$$;

-- ─── 4. Authoritative lifecycle function with real manager/lead gating ─────
-- Converge the active database and the one-shot fresh schema on one set of
-- non-overlapping policies. PostgreSQL combines policies with OR, so leaving
-- even one older broad policy in place would keep the original access gap.
alter table public.projects enable row level security;
alter table public.project_members enable row level security;
alter table public.milestones enable row level security;
alter table public.tasks enable row level security;
alter table public.subtasks enable row level security;
alter table public.task_progress_updates enable row level security;
alter table public.task_status_history enable row level security;
alter table public.task_activities enable row level security;
alter table public.task_attachments enable row level security;
alter table public.audit_events enable row level security;

do $$
declare
  policy_row record;
begin
  for policy_row in
    select schemaname, tablename, policyname
    from pg_policies
    where schemaname = 'public'
      and tablename in (
        'projects',
        'project_members',
        'milestones',
        'tasks',
        'subtasks',
        'task_progress_updates',
        'task_status_history',
        'task_activities',
        'task_attachments',
        'audit_events'
      )
  loop
    execute format(
      'drop policy if exists %I on %I.%I',
      policy_row.policyname,
      policy_row.schemaname,
      policy_row.tablename
    );
  end loop;
end;
$$;

create policy projects_read on public.projects
  for select to authenticated
  using (public.can_see_project(id, auth.uid()));
create policy projects_insert on public.projects
  for insert to authenticated
  with check (
    public.auth_role(auth.uid()) = 'super_admin'
    or (
      public.auth_role(auth.uid()) in ('dept_head', 'department_head')
      and public.org_in_my_subtree(org_id, auth.uid())
      and created_by = auth.uid()
    )
  );
create policy projects_update on public.projects
  for update to authenticated
  using (public.can_manage_project(id, auth.uid()))
  with check (public.can_manage_project(id, auth.uid()));
create policy projects_delete on public.projects
  for delete to authenticated
  using (public.can_manage_project(id, auth.uid()));

create policy project_members_read on public.project_members
  for select to authenticated
  using (public.can_see_project(project_id, auth.uid()));
create policy project_members_insert on public.project_members
  for insert to authenticated
  with check (public.can_manage_project(project_id, auth.uid()));
create policy project_members_update on public.project_members
  for update to authenticated
  using (public.can_manage_project(project_id, auth.uid()))
  with check (public.can_manage_project(project_id, auth.uid()));
create policy project_members_delete on public.project_members
  for delete to authenticated
  using (public.can_manage_project(project_id, auth.uid()));

create policy milestones_read on public.milestones
  for select to authenticated
  using (public.can_see_project(project_id, auth.uid()));
create policy milestones_insert on public.milestones
  for insert to authenticated
  with check (public.can_manage_project(project_id, auth.uid()));
create policy milestones_update on public.milestones
  for update to authenticated
  using (public.can_manage_project(project_id, auth.uid()))
  with check (public.can_manage_project(project_id, auth.uid()));
create policy milestones_delete on public.milestones
  for delete to authenticated
  using (public.can_manage_project(project_id, auth.uid()));

create policy tasks_read on public.tasks
  for select to authenticated
  using (deleted_at is null and public.can_see_task(id, auth.uid()));
create policy tasks_insert on public.tasks
  for insert to authenticated
  with check (
    public.auth_role(auth.uid()) = 'super_admin'
    or (
      public.auth_role(auth.uid()) in ('dept_head', 'department_head')
      and public.org_in_my_subtree(org_id, auth.uid())
      and created_by = auth.uid()
    )
  );
create policy tasks_update on public.tasks
  for update to authenticated
  using (public.can_manage_task(id, auth.uid()))
  with check (public.can_manage_task(id, auth.uid()));
create policy tasks_delete on public.tasks
  for delete to authenticated
  using (public.can_manage_task(id, auth.uid()));

create policy subtasks_read on public.subtasks
  for select to authenticated
  using (public.can_see_task(task_id, auth.uid()));
create policy subtasks_insert on public.subtasks
  for insert to authenticated
  with check (public.can_contribute_task(task_id, auth.uid()));
create policy subtasks_update on public.subtasks
  for update to authenticated
  using (public.can_contribute_task(task_id, auth.uid()))
  with check (public.can_contribute_task(task_id, auth.uid()));
create policy subtasks_delete on public.subtasks
  for delete to authenticated
  using (public.can_contribute_task(task_id, auth.uid()));

create policy task_progress_read on public.task_progress_updates
  for select to authenticated
  using (public.can_see_task(task_id, auth.uid()));

create policy task_history_read on public.task_status_history
  for select to authenticated
  using (public.can_see_task(task_id, auth.uid()));

create policy task_activities_read on public.task_activities
  for select to authenticated
  using (public.can_see_task(task_id, auth.uid()));

create policy task_attachments_read on public.task_attachments
  for select to authenticated
  using (public.can_see_task(task_id, auth.uid()));
create policy task_attachments_insert on public.task_attachments
  for insert to authenticated
  with check (
    public.can_contribute_task(task_id, auth.uid())
    and uploaded_by = auth.uid()
  );
create policy task_attachments_delete on public.task_attachments
  for delete to authenticated
  using (
    uploaded_by = auth.uid()
    or public.can_manage_task(task_id, auth.uid())
  );

create policy audit_insert_self on public.audit_events
  for insert to authenticated
  with check (actor_id = auth.uid());
create policy audit_read_scoped on public.audit_events
  for select to authenticated
  using (
    public.auth_role(auth.uid()) = 'super_admin'
    or actor_id = auth.uid()
    or (
      public.auth_role(auth.uid()) in ('dept_head', 'department_head')
      and public.org_in_my_subtree(org_id, auth.uid())
    )
  );

-- Keep this repair runnable even when the earlier task-lifecycle migration was
-- not installed. The transition helper and write guard are dependencies of the
-- authoritative commands and trigger defined below.
create or replace function public.is_allowed_task_transition(
  from_status text,
  to_status text
)
returns boolean
language sql
immutable
set search_path = public
as $$
  select (from_status, to_status) in (
    ('pending_assignment', 'todo'),
    ('todo', 'in_progress'),
    ('in_progress', 'for_review'),
    ('for_review', 'completed'),
    ('for_review', 'changes_requested'),
    ('changes_requested', 'in_progress'),
    ('completed', 'in_progress')
  );
$$;

create or replace function public.guard_task_status_write()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if new.status is distinct from old.status
     and coalesce(
       current_setting('eflow.allow_status_write', true),
       'off'
     ) <> 'on' then
    raise exception
      'Task status may only change through transition_task_status()'
      using errcode = '42501';
  end if;
  return new;
end;
$$;

create or replace function public.transition_task_status(
  p_task_id uuid,
  p_to_status text,
  p_feedback text default null,
  p_reason text default null
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
  prev_status text;
  is_manager boolean;
  is_reviewer boolean;
  recipient uuid;
begin
  if caller is null then
    raise exception 'Not authenticated' using errcode = '42501';
  end if;

  select role::text, full_name
    into caller_role, caller_name
  from public.profiles
  where id = caller;

  select *
    into t
  from public.tasks
  where id = p_task_id
    and deleted_at is null
  for update;
  if not found then raise exception 'Task not found'; end if;
  prev_status := t.status;

  if t.archived_at is not null then
    raise exception 'Archived tasks cannot change status'
      using errcode = '22023';
  end if;
  if not public.can_see_task(t.id, caller) then
    raise exception 'Task is outside your allowed scope'
      using errcode = '42501';
  end if;
  if p_to_status = prev_status then
    raise exception 'Task is already %', replace(prev_status, '_', ' ')
      using errcode = '22023';
  end if;

  is_manager := public.can_manage_task(t.id, caller);
  is_reviewer := (
    t.assigned_to is distinct from caller
    and (
      caller_role = 'super_admin'
      or (
        caller_role in ('dept_head', 'department_head')
        and public.org_in_my_subtree(t.org_id, caller)
      )
      or t.created_by = caller
      or t.recommendation_lead_id = caller
    )
  );

  if not public.is_allowed_task_transition(t.status, p_to_status) then
    raise exception 'Illegal task transition: % -> %', t.status, p_to_status
      using errcode = '22023';
  end if;

  if p_to_status = 'todo' and t.status = 'pending_assignment' then
    if not is_manager then
      raise exception 'Only a manager may assign work' using errcode = '42501';
    end if;
    if t.assigned_to is null then
      raise exception 'Assign an owner before moving to To do' using errcode = '22023';
    end if;
  elsif p_to_status = 'in_progress' and t.status = 'todo' then
    if not public.can_contribute_task(t.id, caller) then
      raise exception 'Only a task participant may start work'
        using errcode = '42501';
    end if;
  elsif p_to_status = 'in_progress' and t.status = 'changes_requested' then
    if not (t.assigned_to = caller or is_manager) then
      raise exception 'Only the assignee may resume rework' using errcode = '42501';
    end if;
  elsif p_to_status = 'for_review' then
    if not (t.assigned_to = caller or is_manager) then
      raise exception 'Only the assignee may submit for review' using errcode = '42501';
    end if;
    if t.latest_submission is null
       or coalesce(btrim(t.latest_submission ->> 'note'), '') = '' then
      raise exception 'A completion note is required before review'
        using errcode = '22023';
    end if;
  elsif p_to_status in ('completed', 'changes_requested') then
    if not is_reviewer then
      raise exception 'Only the designated reviewer may decide a review'
        using errcode = '42501';
    end if;
    if p_to_status = 'changes_requested'
       and coalesce(btrim(p_feedback), '') = '' then
      raise exception 'Feedback is required when requesting changes'
        using errcode = '22023';
    end if;
  elsif p_to_status = 'in_progress' and t.status = 'completed' then
    if not is_manager then
      raise exception 'Only a manager may reopen a completed task'
        using errcode = '42501';
    end if;
    if coalesce(btrim(p_reason), '') = '' then
      raise exception 'A reason is required to reopen'
        using errcode = '22023';
    end if;
  end if;

  perform set_config('eflow.allow_status_write', 'on', true);

  update public.tasks
  set
    status = p_to_status,
    percent_complete = case
      when p_to_status in ('for_review', 'completed') then 100
      when p_to_status = 'in_progress'
       and prev_status in ('changes_requested', 'completed')
       and percent_complete >= 100 then 99
      else percent_complete
    end,
    feedback = case
      when p_to_status in ('completed', 'changes_requested') then p_feedback
      else feedback
    end,
    rejection_note = case
      when p_to_status = 'changes_requested' then coalesce(p_feedback, p_reason)
      when p_to_status = 'completed' then null
      else rejection_note
    end,
    rejected_at = case
      when p_to_status = 'changes_requested' then now()
      when p_to_status = 'completed' then null
      else rejected_at
    end,
    reopen_reason = case
      when prev_status = 'completed' and p_to_status = 'in_progress'
        then p_reason
      else reopen_reason
    end,
    reopened_at = case
      when prev_status = 'completed' and p_to_status = 'in_progress'
        then now()
      else reopened_at
    end,
    reopened_by_id = case
      when prev_status = 'completed' and p_to_status = 'in_progress'
        then caller
      else reopened_by_id
    end,
    last_activity_at = now()
  where id = p_task_id
  returning * into t;

  perform set_config('eflow.allow_status_write', 'off', true);

  insert into public.task_status_history (
    task_id,
    from_status,
    to_status,
    actor_id,
    actor_name,
    note
  )
  values (
    p_task_id,
    prev_status,
    p_to_status,
    caller,
    coalesce(caller_name, 'User'),
    coalesce(p_feedback, p_reason)
  );

  insert into public.task_activities (
    task_id,
    type,
    content,
    actor_id,
    actor_name
  )
  values (
    p_task_id,
    p_to_status,
    coalesce(
      p_feedback,
      p_reason,
      'Status changed to ' || replace(p_to_status, '_', ' ')
    ),
    caller,
    coalesce(caller_name, 'User')
  );

  insert into public.audit_events (
    actor_id,
    actor_name,
    entity_type,
    entity_id,
    action,
    reason,
    before_data,
    after_data,
    org_id
  )
  values (
    caller,
    coalesce(caller_name, 'User'),
    'task',
    p_task_id::text,
    'task.transition.' || p_to_status,
    coalesce(p_reason, p_feedback),
    jsonb_build_object('status', prev_status),
    jsonb_build_object(
      'status',
      p_to_status,
      'percent_complete',
      t.percent_complete
    ),
    t.org_id
  );

  if p_to_status = 'for_review' then
    recipient := case
      when t.recommendation_lead_id is not null
       and t.recommendation_lead_id <> caller
        then t.recommendation_lead_id
      else t.created_by
    end;
  else
    recipient := t.assigned_to;
  end if;

  if recipient is not null and recipient <> caller then
    insert into public.notifications (
      user_id,
      type,
      title,
      message,
      task_id,
      task_title,
      actor_id,
      actor_name,
      status_from,
      status_to,
      reason
    )
    values (
      recipient,
      case
        when p_to_status = 'completed' then 'completed'
        when p_to_status = 'for_review' then 'approval_needed'
        else 'status_change'
      end,
      'Task ' || replace(p_to_status, '_', ' '),
      coalesce(caller_name, 'Someone') || ' moved "' || t.title ||
        '" to ' || replace(p_to_status, '_', ' ') || '.',
      p_task_id,
      t.title,
      caller,
      coalesce(caller_name, 'User'),
      prev_status,
      p_to_status,
      coalesce(p_reason, p_feedback, '')
    );
  end if;

  return t;
end;
$$;

create or replace function public.assign_task(
  p_task_id uuid,
  p_assignee uuid,
  p_assignee_name text default null
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
  prev_status text;
  is_manager boolean;
  previous_assignee uuid;
  resolved_assignee_name text;
  assignee_org uuid;
  assignee_active boolean;
begin
  if caller is null then
    raise exception 'Not authenticated' using errcode = '42501';
  end if;

  select role::text, full_name
    into caller_role, caller_name
  from public.profiles
  where id = caller;

  select *
    into t
  from public.tasks
  where id = p_task_id
    and deleted_at is null
  for update;
  if not found then raise exception 'Task not found'; end if;
  prev_status := t.status;
  previous_assignee := t.assigned_to;

  if t.archived_at is not null then
    raise exception 'Archived tasks cannot be reassigned'
      using errcode = '22023';
  end if;
  if t.status in ('for_review', 'completed') then
    raise exception 'Reviewed work must be reopened before reassignment'
      using errcode = '22023';
  end if;

  is_manager := public.can_manage_task(t.id, caller);
  if not is_manager then
    raise exception 'Not allowed to assign this task' using errcode = '42501';
  end if;

  if p_assignee is null then
    if t.status not in ('pending_assignment', 'todo') then
      raise exception 'Active work must be reopened or reassigned, not cleared'
        using errcode = '22023';
    end if;
    resolved_assignee_name := '';
  else
    select full_name, org_id, is_active
      into resolved_assignee_name, assignee_org, assignee_active
    from public.profiles
    where id = p_assignee;
    if not found or not coalesce(assignee_active, false) then
      raise exception 'Assignee is not an active profile'
        using errcode = '22023';
    end if;

    if caller_role <> 'super_admin' then
      if caller_role in ('dept_head', 'department_head') then
        if not public.org_in_my_subtree(assignee_org, caller) then
          raise exception 'Assignee is outside your organization scope'
            using errcode = '42501';
        end if;
      elsif assignee_org is distinct from t.org_id then
        raise exception 'Task leads may assign only within the task organization'
          using errcode = '42501';
      end if;
    end if;
  end if;

  perform set_config('eflow.allow_status_write', 'on', true);
  update public.tasks
  set
    assigned_to = p_assignee,
    assignee_name = resolved_assignee_name,
    status = case
      when p_assignee is not null and status = 'pending_assignment' then 'todo'
      when p_assignee is null then 'pending_assignment'
      else status
    end,
    last_activity_at = now()
  where id = p_task_id
  returning * into t;
  perform set_config('eflow.allow_status_write', 'off', true);

  if t.status is distinct from prev_status then
    insert into public.task_status_history (
      task_id,
      from_status,
      to_status,
      actor_id,
      actor_name,
      note
    )
    values (
      p_task_id,
      prev_status,
      t.status,
      caller,
      coalesce(caller_name, 'User'),
      'Assignment'
    );
  end if;

  insert into public.task_activities (
    task_id,
    type,
    content,
    actor_id,
    actor_name
  )
  values (
    p_task_id,
    'assigned',
    case
      when p_assignee is null then 'Assignment cleared'
      else 'Assigned to ' || resolved_assignee_name
    end,
    caller,
    coalesce(caller_name, 'User')
  );

  insert into public.audit_events (
    actor_id,
    actor_name,
    entity_type,
    entity_id,
    action,
    before_data,
    after_data,
    org_id
  )
  values (
    caller,
    coalesce(caller_name, 'User'),
    'task',
    p_task_id::text,
    'task.assigned',
    jsonb_build_object('assigned_to', previous_assignee, 'status', prev_status),
    jsonb_build_object('assigned_to', p_assignee, 'status', t.status),
    t.org_id
  );

  if p_assignee is not null and p_assignee <> caller then
    insert into public.notifications (
      user_id,
      type,
      title,
      message,
      task_id,
      task_title,
      actor_id,
      actor_name,
      status_to
    )
    values (
      p_assignee,
      'assignment',
      'New Task Assigned',
      'You have been assigned to "' || t.title || '".',
      p_task_id,
      t.title,
      caller,
      coalesce(caller_name, 'User'),
      t.status
    );
  end if;

  return t;
end;
$$;

-- ─── 5. Atomic structured progress command ────────────────────────────────
create or replace function public.submit_task_progress(
  p_task_id uuid,
  p_percent_complete int default null,
  p_blocker_category text default null,
  p_blocker text default null,
  p_next_step text default null,
  p_note text default null,
  p_attachment_path text default null,
  p_attachment_name text default null
)
returns public.task_progress_updates
language plpgsql
security definer
set search_path = public
as $$
declare
  caller uuid := auth.uid();
  caller_name text;
  t public.tasks;
  progress public.task_progress_updates;
begin
  if caller is null then
    raise exception 'Not authenticated' using errcode = '42501';
  end if;
  if p_percent_complete is not null
     and (p_percent_complete < 0 or p_percent_complete > 100) then
    raise exception 'Progress must be between 0 and 100'
      using errcode = '22023';
  end if;

  select full_name
    into caller_name
  from public.profiles
  where id = caller;

  select *
    into t
  from public.tasks
  where id = p_task_id
    and deleted_at is null
  for update;
  if not found then raise exception 'Task not found'; end if;

  if t.archived_at is not null then
    raise exception 'Archived tasks cannot receive progress'
      using errcode = '22023';
  end if;
  if not public.can_contribute_task(t.id, caller) then
    raise exception 'Only a task participant may post progress'
      using errcode = '42501';
  end if;
  if t.status not in ('todo', 'in_progress') then
    raise exception 'Resume or reopen this task before posting progress'
      using errcode = '22023';
  end if;

  if t.status = 'todo' and coalesce(p_percent_complete, 0) > 0 then
    perform public.transition_task_status(
      p_task_id,
      'in_progress',
      null,
      'Work started with a progress update'
    );
  end if;

  insert into public.task_progress_updates (
    task_id,
    author_id,
    author_name,
    percent_complete,
    blocker_category,
    blocker,
    next_step,
    note,
    attachment_path,
    attachment_name
  )
  values (
    p_task_id,
    caller,
    coalesce(caller_name, 'User'),
    p_percent_complete,
    nullif(btrim(p_blocker_category), ''),
    nullif(btrim(p_blocker), ''),
    nullif(btrim(p_next_step), ''),
    nullif(btrim(p_note), ''),
    p_attachment_path,
    p_attachment_name
  )
  returning * into progress;

  update public.tasks
  set
    percent_complete = coalesce(p_percent_complete, percent_complete),
    last_activity_at = now()
  where id = p_task_id;

  insert into public.audit_events (
    actor_id,
    actor_name,
    entity_type,
    entity_id,
    action,
    after_data,
    metadata,
    org_id
  )
  values (
    caller,
    coalesce(caller_name, 'User'),
    'task',
    p_task_id::text,
    'progress.updated',
    jsonb_build_object(
      'percentComplete',
      p_percent_complete,
      'blocker',
      nullif(btrim(p_blocker), '')
    ),
    jsonb_build_object('progressId', progress.id),
    t.org_id
  );

  return progress;
end;
$$;

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
  normalized_submission jsonb;
  t public.tasks;
begin
  if caller is null then
    raise exception 'Not authenticated' using errcode = '42501';
  end if;

  completion_note := nullif(btrim(p_submission ->> 'note'), '');
  if completion_note is null then
    raise exception 'Completion note is required'
      using errcode = '22023';
  end if;
  if p_submission ? 'attachments'
     and jsonb_typeof(p_submission -> 'attachments') <> 'array' then
    raise exception 'Submission attachments must be an array'
      using errcode = '22023';
  end if;

  select full_name
    into caller_name
  from public.profiles
  where id = caller;

  select *
    into t
  from public.tasks
  where id = p_task_id
    and deleted_at is null
  for update;
  if not found then raise exception 'Task not found'; end if;
  if t.archived_at is not null or t.status <> 'in_progress' then
    raise exception 'Only in-progress work can be submitted'
      using errcode = '22023';
  end if;
  if not (
    t.assigned_to = caller
    or t.recommendation_lead_id = caller
  ) then
    raise exception 'Only the assignee or task lead may submit this work'
      using errcode = '42501';
  end if;

  normalized_submission := jsonb_build_object(
    'note', completion_note,
    'submitterId', caller::text,
    'submitterName', coalesce(caller_name, 'User'),
    'submittedAt', floor(extract(epoch from clock_timestamp()) * 1000)::bigint,
    'attachments', coalesce(p_submission -> 'attachments', '[]'::jsonb)
  );

  update public.tasks
  set
    latest_submission = normalized_submission,
    rejection_note = null,
    rejected_at = null,
    feedback = null,
    percent_complete = 100,
    last_activity_at = now()
  where id = p_task_id;

  select public.transition_task_status(
    p_task_id,
    'for_review',
    null,
    completion_note
  )
  into t;

  return t;
end;
$$;

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
  decided public.tasks;
begin
  if p_approve and coalesce(btrim(p_audit_hash), '') = '' then
    raise exception 'Approval audit hash is required'
      using errcode = '22023';
  end if;
  if not p_approve and coalesce(btrim(p_feedback), '') = '' then
    raise exception 'Feedback is required when requesting changes'
      using errcode = '22023';
  end if;

  select public.transition_task_status(
    p_task_id,
    case when p_approve then 'completed' else 'changes_requested' end,
    nullif(btrim(p_feedback), ''),
    null
  )
  into decided;

  if p_approve then
    update public.tasks
    set audit_hash = p_audit_hash
    where id = p_task_id
    returning * into decided;
  end if;

  return decided;
end;
$$;

revoke all on function public.transition_task_status(uuid, text, text, text)
  from public, anon;
revoke all on function public.assign_task(uuid, uuid, text)
  from public, anon;
revoke all on function public.submit_task_progress(
  uuid, int, text, text, text, text, text, text
) from public, anon;
revoke all on function public.submit_task_for_review(uuid, jsonb)
  from public, anon;
revoke all on function public.decide_task_review(uuid, boolean, text, text)
  from public, anon;

grant execute on function public.transition_task_status(uuid, text, text, text)
  to authenticated;
grant execute on function public.assign_task(uuid, uuid, text)
  to authenticated;
grant execute on function public.submit_task_progress(
  uuid,
  int,
  text,
  text,
  text,
  text,
  text,
  text
) to authenticated;
grant execute on function public.submit_task_for_review(uuid, jsonb)
  to authenticated;
grant execute on function public.decide_task_review(uuid, boolean, text, text)
  to authenticated;

-- ─── 6. Subtask → parent task progress roll-up ─────────────────────────────
drop function if exists public.refresh_task_subtask_rollup(uuid);
create function public.refresh_task_subtask_rollup(
  target_task uuid,
  touch_activity boolean default true
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  parent_task public.tasks;
  total_count int;
  completed_count int;
  next_percent int;
  next_status text;
  caller uuid := auth.uid();
  caller_name text;
begin
  select *
    into parent_task
  from public.tasks
  where id = target_task
    and deleted_at is null
  for update;
  if not found then return; end if;

  select
    count(*)::int,
    count(*) filter (where is_completed)::int
  into total_count, completed_count
  from public.subtasks
  where task_id = target_task;

  next_status := parent_task.status;
  next_percent := case
    when parent_task.status in ('for_review', 'completed') then 100
    when parent_task.status = 'pending_assignment' then 0
    when total_count = 0 then 0
    else round((completed_count::numeric / total_count::numeric) * 100)::int
  end;

  if parent_task.status = 'todo' and completed_count > 0 then
    next_status := 'in_progress';
  end if;

  if parent_task.subtask_count is not distinct from total_count
     and parent_task.subtask_completed_count is not distinct from completed_count
     and parent_task.percent_complete is not distinct from next_percent
     and parent_task.status is not distinct from next_status then
    return;
  end if;

  if next_status is distinct from parent_task.status then
    perform set_config('eflow.allow_status_write', 'on', true);
  end if;

  update public.tasks
  set
    subtask_count = total_count,
    subtask_completed_count = completed_count,
    percent_complete = next_percent,
    status = next_status,
    last_activity_at = case
      when touch_activity then now()
      else last_activity_at
    end
  where id = target_task;

  if next_status is distinct from parent_task.status then
    perform set_config('eflow.allow_status_write', 'off', true);

    select full_name
      into caller_name
    from public.profiles
    where id = caller;

    insert into public.task_status_history (
      task_id,
      from_status,
      to_status,
      actor_id,
      actor_name,
      note
    )
    values (
      target_task,
      parent_task.status,
      next_status,
      caller,
      coalesce(caller_name, 'System'),
      'Work started by completing a subtask'
    );

    insert into public.task_activities (
      task_id,
      type,
      content,
      actor_id,
      actor_name
    )
    values (
      target_task,
      next_status,
      'Work started by completing a subtask',
      caller,
      coalesce(caller_name, 'System')
    );

    insert into public.audit_events (
      actor_id,
      actor_name,
      entity_type,
      entity_id,
      action,
      before_data,
      after_data,
      org_id
    )
    values (
      caller,
      coalesce(caller_name, 'System'),
      'task',
      target_task::text,
      'task.transition.in_progress',
      jsonb_build_object(
        'status', parent_task.status,
        'percent_complete', parent_task.percent_complete
      ),
      jsonb_build_object(
        'status', next_status,
        'percent_complete', next_percent
      ),
      parent_task.org_id
    );
  end if;
end;
$$;

create or replace function public.guard_subtask_mutation()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  target_task uuid;
  parent_status text;
begin
  target_task := case when tg_op = 'DELETE' then old.task_id else new.task_id end;
  select status
    into parent_status
  from public.tasks
  where id = target_task
    and deleted_at is null;

  if parent_status in ('for_review', 'completed') then
    raise exception 'Subtasks are locked while work is under review or completed'
      using errcode = '22023';
  end if;

  if tg_op = 'UPDATE' and old.task_id is distinct from new.task_id then
    select status
      into parent_status
    from public.tasks
    where id = old.task_id
      and deleted_at is null;
    if parent_status in ('for_review', 'completed') then
      raise exception 'Subtasks are locked while work is under review or completed'
        using errcode = '22023';
    end if;
  end if;

  if tg_op = 'DELETE' then return old; end if;
  return new;
end;
$$;

create or replace function public.rollup_task_subtasks()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if tg_op = 'DELETE' then
    perform public.refresh_task_subtask_rollup(old.task_id, true);
    return old;
  end if;

  if tg_op = 'UPDATE' and old.task_id is distinct from new.task_id then
    perform public.refresh_task_subtask_rollup(old.task_id, true);
  end if;
  perform public.refresh_task_subtask_rollup(new.task_id, true);
  return new;
end;
$$;

drop trigger if exists subtasks_recount on public.subtasks;
drop trigger if exists subtasks_sync_counts on public.subtasks;
drop trigger if exists subtasks_rollup_parent on public.subtasks;
drop trigger if exists subtasks_guard_terminal on public.subtasks;

create trigger subtasks_guard_terminal
before insert or update or delete
on public.subtasks
for each row
execute function public.guard_subtask_mutation();

create trigger subtasks_rollup_parent
after insert or update of is_completed, task_id or delete
on public.subtasks
for each row
execute function public.rollup_task_subtasks();

revoke all on function public.refresh_task_subtask_rollup(uuid, boolean)
  from public, anon, authenticated;
revoke all on function public.guard_subtask_mutation()
  from public, anon, authenticated;
revoke all on function public.rollup_task_subtasks()
  from public, anon, authenticated;

-- Initialize counters without manufacturing user activity timestamps.
do $$
declare
  task_row record;
begin
  for task_row in
    select id from public.tasks where deleted_at is null
  loop
    perform public.refresh_task_subtask_rollup(task_row.id, false);
  end loop;
end;
$$;

-- A milestone can only be linked to a task in the same canonical project.
create or replace function public.guard_task_project_links()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if new.milestone_id is null then return new; end if;
  if new.linked_project_id is null then
    raise exception 'A milestone link requires a canonical project link'
      using errcode = '23514';
  end if;
  if not exists (
    select 1
    from public.milestones
    where id = new.milestone_id
      and project_id = new.linked_project_id
  ) then
    raise exception 'Milestone does not belong to the linked project'
      using errcode = '23514';
  end if;
  return new;
end;
$$;

drop trigger if exists tasks_guard_project_links on public.tasks;
create trigger tasks_guard_project_links
before insert or update of linked_project_id, milestone_id
on public.tasks
for each row
execute function public.guard_task_project_links();

create or replace function public.record_initial_task_lifecycle()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  caller uuid := auth.uid();
  caller_name text;
begin
  select full_name
    into caller_name
  from public.profiles
  where id = caller;

  insert into public.task_status_history (
    task_id,
    from_status,
    to_status,
    actor_id,
    actor_name,
    note
  )
  values (
    new.id,
    null,
    new.status,
    caller,
    coalesce(caller_name, 'System'),
    'Task created'
  );

  insert into public.task_activities (
    task_id,
    type,
    content,
    actor_id,
    actor_name
  )
  values (
    new.id,
    'created',
    'Task created',
    caller,
    coalesce(caller_name, 'System')
  );

  insert into public.audit_events (
    actor_id,
    actor_name,
    entity_type,
    entity_id,
    action,
    after_data,
    org_id
  )
  values (
    caller,
    coalesce(caller_name, 'System'),
    'task',
    new.id::text,
    'task.created',
    jsonb_build_object(
      'status', new.status,
      'assigned_to', new.assigned_to,
      'linked_project_id', new.linked_project_id
    ),
    new.org_id
  );

  return new;
end;
$$;

drop trigger if exists tasks_record_initial_lifecycle on public.tasks;
create trigger tasks_record_initial_lifecycle
after insert on public.tasks
for each row
execute function public.record_initial_task_lifecycle();

-- Reattach the lifecycle guard so incremental and one-shot installs converge.
drop trigger if exists guard_task_status_write on public.tasks;
create trigger guard_task_status_write
before update on public.tasks
for each row
execute function public.guard_task_status_write();

drop trigger if exists tasks_sync_project_members on public.tasks;
drop function if exists public.sync_task_project_members();

do $$
begin
  if not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'project_members'
  ) then
    alter publication supabase_realtime add table public.project_members;
  end if;
exception
  when duplicate_object or undefined_object then null;
end;
$$;
