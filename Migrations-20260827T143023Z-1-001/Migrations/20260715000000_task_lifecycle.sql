-- ════════════════════════════════════════════════════════════════════════════
-- Task Flow Stabilization — Phases 0.3 / 2 / 4 (forward migration)
-- ────────────────────────────────────────────────────────────────────────────
-- The live database is built from incremental migrations; the authoritative
-- task lifecycle designed in fresh_schema.sql was never applied to it. This
-- migration ports that backend WITHOUT a destructive rebuild:
--
--   • adds the plan's `changes_requested` status;
--   • normalizes broken assignment state (Phase 0.3) BEFORE adding constraints;
--   • adds the assignment/status consistency constraints;
--   • creates the one protected transition entry point + assignment RPC (§2.2);
--   • attaches the guard trigger so status can ONLY change through the RPC;
--   • replaces the `using (true)` discussion read policies with task scope (§4).
--
-- Depends on helpers already present from 20260712000000_core_workflow.sql:
--   is_super_admin(), org_in_my_subtree(), can_see_project(), auth_role().
-- Idempotent: safe to re-run.
-- ════════════════════════════════════════════════════════════════════════════

-- ─── 1. Allow the new status value ────────────────────────────────────────────
-- The original CHECK was created outside migrations (default name tasks_status_check).
alter table public.tasks drop constraint if exists tasks_status_check;
alter table public.tasks
  add constraint tasks_status_check check (status in (
    'pending_assignment','todo','in_progress','for_review','changes_requested','completed'
  ));

-- ─── 2. Phase 0.3 — normalize assignment state (must precede constraints) ─────
-- These run before the guard trigger exists, so direct status writes are allowed.

-- 2a. Assigned but still pending_assignment → advance to todo (8-of-8 finding).
with moved as (
  update public.tasks
     set status = 'todo', last_activity_at = now()
   where deleted_at is null
     and status = 'pending_assignment'
     and assigned_to is not null
  returning id
)
insert into public.task_status_history (task_id, from_status, to_status, actor_name, note)
select id, 'pending_assignment', 'todo', 'System (migration)',
       'Assignment state normalized — Phase 0.3'
  from moved;

-- 2b. Active status but no assignee → return to pending_assignment (stale metadata).
with moved as (
  update public.tasks
     set status = 'pending_assignment', last_activity_at = now()
   where deleted_at is null
     and status in ('todo','in_progress','for_review','changes_requested')
     and assigned_to is null
  returning id
)
insert into public.task_status_history (task_id, from_status, to_status, actor_name, note)
select id, 'unknown', 'pending_assignment', 'System (migration)',
       'Cleared active status with no assignee — Phase 0.3'
  from moved;

-- One concise audit event for the whole repair batch (no per-employee spam).
insert into public.audit_events (actor_name, entity_type, entity_id, action, reason)
values ('System (migration)', 'task', 'batch', 'task.data_repaired',
        'Phase 0.3 assignment-state normalization');

-- ─── 3. Assignment/status consistency constraints (§0.3) ──────────────────────
alter table public.tasks drop constraint if exists tasks_assignment_consistent;
alter table public.tasks
  add constraint tasks_assignment_consistent check (
    (status = 'pending_assignment' and assigned_to is null)
    or (status in ('todo','in_progress','for_review','changes_requested','completed'))
  );

alter table public.tasks drop constraint if exists tasks_active_needs_assignee;
alter table public.tasks
  add constraint tasks_active_needs_assignee check (
    status not in ('todo','in_progress','for_review','changes_requested')
    or assigned_to is not null
  );

-- ─── 4. task_activities timeline table (§2.2 side effect target) ──────────────
create table if not exists public.task_activities (
  id         uuid primary key default gen_random_uuid(),
  task_id    uuid not null references public.tasks(id) on delete cascade,
  type       text not null default '',
  content    text not null default '',
  actor_id   uuid references public.profiles(id) on delete set null,
  actor_name text default 'System',
  created_at timestamptz not null default now()
);
create index if not exists task_activities_task_idx on public.task_activities(task_id, created_at desc);

-- ─── 5. can_see_task — drives discussion/attachment RLS (§4) ──────────────────
create or replace function public.can_see_task(target_task uuid, caller_id uuid)
returns boolean language plpgsql stable security definer set search_path = public as $$
declare
  t_assignee uuid; t_creator uuid; t_org uuid; t_project uuid;
begin
  if public.is_super_admin(caller_id) then return true; end if;
  select assigned_to, created_by, org_id, linked_project_id
    into t_assignee, t_creator, t_org, t_project
  from public.tasks where id = target_task;
  if not found then return false; end if;
  return (
    t_assignee = caller_id
    or t_creator = caller_id
    or public.org_in_my_subtree(t_org, caller_id)
    or (t_project is not null and public.can_see_project(t_project, caller_id))
  );
end;
$$;

-- ─── 6. Transition table (§2.1) ──────────────────────────────────────────────
create or replace function public.is_allowed_task_transition(from_status text, to_status text)
returns boolean language sql immutable as $$
  select (from_status, to_status) in (
    ('pending_assignment','todo'),
    ('todo','in_progress'),
    ('in_progress','for_review'),
    ('for_review','completed'),
    ('for_review','changes_requested'),
    ('changes_requested','in_progress'),
    ('completed','in_progress'),
    ('pending_assignment','pending_assignment'),
    ('todo','todo'),('in_progress','in_progress'),('for_review','for_review'),
    ('changes_requested','changes_requested'),('completed','completed')
  );
$$;

-- ─── 7. Guard: only transition_task_status()/assign_task() may change status ──
create or replace function public.guard_task_status_write()
returns trigger language plpgsql set search_path = public as $$
begin
  if new.status is distinct from old.status then
    if coalesce(current_setting('eflow.allow_status_write', true), 'off') <> 'on' then
      raise exception 'Task status may only change through transition_task_status()'
        using errcode = '42501';
    end if;
  end if;
  return new;
end;
$$;

-- ─── 8. The one protected transition entry point (§2.2) ───────────────────────
create or replace function public.transition_task_status(
  p_task_id uuid,
  p_to_status text,
  p_feedback text default null,
  p_reason text default null
)
returns public.tasks language plpgsql security definer set search_path = public as $$
declare
  caller uuid := auth.uid();
  caller_role text;
  caller_name text;
  t public.tasks;
  prev_status text;
  is_manager boolean;
  recipient uuid;
begin
  if caller is null then raise exception 'Not authenticated' using errcode = '42501'; end if;

  select role, full_name into caller_role, caller_name from public.profiles where id = caller;

  select * into t from public.tasks where id = p_task_id and deleted_at is null;
  if not found then raise exception 'Task not found'; end if;
  prev_status := t.status;

  is_manager := public.is_super_admin(caller)
                or public.org_in_my_subtree(t.org_id, caller)
                or t.created_by = caller;

  if not public.is_allowed_task_transition(t.status, p_to_status) then
    raise exception 'Illegal task transition: % -> %', t.status, p_to_status using errcode = '22023';
  end if;

  -- Per-transition authorization + required evidence.
  if p_to_status = 'todo' and t.status = 'pending_assignment' then
    if not is_manager then raise exception 'Only a manager may assign work' using errcode='42501'; end if;
    if t.assigned_to is null then raise exception 'Assign an owner before moving to To do' using errcode='22023'; end if;
  elsif p_to_status = 'in_progress' and t.status = 'todo' then
    if not (t.assigned_to = caller or is_manager) then raise exception 'Only the assignee may start work' using errcode='42501'; end if;
  elsif p_to_status = 'in_progress' and t.status = 'changes_requested' then
    if not (t.assigned_to = caller or is_manager) then raise exception 'Only the assignee may resume rework' using errcode='42501'; end if;
  elsif p_to_status = 'for_review' then
    if not (t.assigned_to = caller or is_manager) then raise exception 'Only the assignee may submit for review' using errcode='42501'; end if;
  elsif p_to_status in ('completed','changes_requested') then
    if not is_manager then raise exception 'Only a reviewer may decide a review' using errcode='42501'; end if;
    if p_to_status = 'changes_requested' and coalesce(btrim(p_feedback),'') = '' then
      raise exception 'Feedback is required when requesting changes' using errcode='22023';
    end if;
  elsif p_to_status = 'in_progress' and t.status = 'completed' then
    if not is_manager then raise exception 'Only a manager may reopen a completed task' using errcode='42501'; end if;
    if coalesce(btrim(p_reason),'') = '' then raise exception 'A reason is required to reopen' using errcode='22023'; end if;
  end if;

  perform set_config('eflow.allow_status_write', 'on', true);

  update public.tasks set
    status         = p_to_status,
    feedback       = case when p_to_status in ('completed','changes_requested') then p_feedback else feedback end,
    rejection_note = case when p_to_status = 'changes_requested' then coalesce(p_feedback, p_reason)
                          when p_to_status = 'completed' then null else rejection_note end,
    rejected_at    = case when p_to_status = 'changes_requested' then now()
                          when p_to_status = 'completed' then null else rejected_at end,
    reopen_reason  = case when prev_status = 'completed' and p_to_status = 'in_progress' then p_reason else reopen_reason end,
    reopened_at    = case when prev_status = 'completed' and p_to_status = 'in_progress' then now() else reopened_at end,
    reopened_by_id = case when prev_status = 'completed' and p_to_status = 'in_progress' then caller else reopened_by_id end,
    last_activity_at = now()
  where id = p_task_id
  returning * into t;

  perform set_config('eflow.allow_status_write', 'off', true);

  insert into public.task_status_history (task_id, from_status, to_status, actor_id, actor_name, note)
  values (p_task_id, prev_status, p_to_status, caller, coalesce(caller_name,'User'), coalesce(p_feedback, p_reason));

  insert into public.task_activities (task_id, type, content, actor_id, actor_name)
  values (p_task_id, p_to_status, coalesce(p_feedback, p_reason, 'Status changed to ' || p_to_status), caller, coalesce(caller_name,'User'));

  insert into public.audit_events (actor_id, actor_name, entity_type, entity_id, action, reason, before_data, after_data, org_id)
  values (caller, coalesce(caller_name,'User'), 'task', p_task_id::text, 'task.transition.' || p_to_status,
          coalesce(p_reason, p_feedback),
          jsonb_build_object('status', prev_status),
          jsonb_build_object('status', p_to_status),
          t.org_id);

  -- Notify the AFFECTED party (§2.3), never just the actor.
  --   submission → creator/reviewer; decision/reopen → assignee.
  if p_to_status = 'for_review' then
    recipient := t.created_by;
  else
    recipient := t.assigned_to;
  end if;
  if recipient is not null and recipient <> caller then
    insert into public.notifications (user_id, type, title, message, task_id, task_title, actor_id, actor_name, status_from, status_to, reason)
    values (recipient,
            case when p_to_status='completed' then 'completed'
                 when p_to_status='for_review' then 'approval_needed'
                 else 'status_change' end,
            'Task ' || replace(p_to_status,'_',' '),
            coalesce(caller_name,'Someone') || ' moved "' || t.title || '" to ' || replace(p_to_status,'_',' ') || '.',
            p_task_id, t.title, caller, coalesce(caller_name,'User'),
            prev_status, p_to_status, coalesce(p_reason, p_feedback, ''));
  end if;

  return t;
end;
$$;

-- ─── 9. Assignment RPC (§2.2) ─────────────────────────────────────────────────
create or replace function public.assign_task(
  p_task_id uuid,
  p_assignee uuid,
  p_assignee_name text default null
)
returns public.tasks language plpgsql security definer set search_path = public as $$
declare
  caller uuid := auth.uid();
  caller_name text;
  t public.tasks;
  prev_status text;
begin
  if caller is null then raise exception 'Not authenticated' using errcode='42501'; end if;
  select full_name into caller_name from public.profiles where id = caller;
  select * into t from public.tasks where id = p_task_id and deleted_at is null;
  if not found then raise exception 'Task not found'; end if;
  prev_status := t.status;

  if not (public.is_super_admin(caller) or public.org_in_my_subtree(t.org_id, caller) or t.created_by = caller) then
    raise exception 'Not allowed to assign this task' using errcode='42501';
  end if;
  if p_assignee is not null and not exists (select 1 from public.profiles where id = p_assignee and is_active) then
    raise exception 'Assignee is not an active profile' using errcode='22023';
  end if;

  perform set_config('eflow.allow_status_write', 'on', true);
  update public.tasks set
    assigned_to   = p_assignee,
    assignee_name = coalesce(p_assignee_name, assignee_name),
    status        = case when p_assignee is not null and status = 'pending_assignment' then 'todo'
                         when p_assignee is null then 'pending_assignment'
                         else status end,
    last_activity_at = now()
  where id = p_task_id
  returning * into t;
  perform set_config('eflow.allow_status_write', 'off', true);

  insert into public.task_status_history (task_id, from_status, to_status, actor_id, actor_name, note)
  values (p_task_id, prev_status, t.status, caller, coalesce(caller_name,'User'), 'Assignment');

  insert into public.task_activities (task_id, type, content, actor_id, actor_name)
  values (p_task_id, 'assigned',
          case when p_assignee is null then 'Assignment cleared'
               else 'Assigned to ' || coalesce(p_assignee_name, 'employee') end,
          caller, coalesce(caller_name,'User'));

  insert into public.audit_events (actor_id, actor_name, entity_type, entity_id, action, after_data, org_id)
  values (caller, coalesce(caller_name,'User'), 'task', p_task_id::text, 'task.assigned',
          jsonb_build_object('assigned_to', p_assignee, 'status', t.status), t.org_id);

  if p_assignee is not null and p_assignee <> caller then
    insert into public.notifications (user_id, type, title, message, task_id, task_title, actor_id, actor_name, status_to)
    values (p_assignee, 'assignment', 'New Task Assigned',
            'You have been assigned to "' || t.title || '".', p_task_id, t.title, caller, coalesce(caller_name,'User'), t.status);
  end if;

  return t;
end;
$$;

grant execute on function public.transition_task_status(uuid, text, text, text) to authenticated;
grant execute on function public.assign_task(uuid, uuid, text) to authenticated;

-- ─── 10. Attach the guard trigger (client now uses the RPCs exclusively) ──────
drop trigger if exists guard_task_status_write on public.tasks;
create trigger guard_task_status_write before update on public.tasks
  for each row execute function public.guard_task_status_write();

-- ─── 11. Phase 4 — replace `using (true)` discussion reads with task scope ────
do $$
begin
  -- task_progress_updates
  drop policy if exists "progress readable to authenticated" on public.task_progress_updates;
  drop policy if exists "progress insert self" on public.task_progress_updates;
  create policy "progress readable in task scope" on public.task_progress_updates
    for select to authenticated using (public.can_see_task(task_id, auth.uid()));
  create policy "progress insert self in scope" on public.task_progress_updates
    for insert to authenticated
    with check (public.can_see_task(task_id, auth.uid()) and author_id = auth.uid());

  -- task_comments
  drop policy if exists "comments readable to authenticated" on public.task_comments;
  drop policy if exists "comments insert self" on public.task_comments;
  create policy "comments readable in task scope" on public.task_comments
    for select to authenticated using (public.can_see_task(task_id, auth.uid()));
  create policy "comments insert self in scope" on public.task_comments
    for insert to authenticated
    with check (public.can_see_task(task_id, auth.uid()) and author_id = auth.uid());

  -- task_comment_attachments
  drop policy if exists "comment attachments readable" on public.task_comment_attachments;
  drop policy if exists "comment attachments insert" on public.task_comment_attachments;
  create policy "comment attachments readable in scope" on public.task_comment_attachments
    for select to authenticated using (
      exists (select 1 from public.task_comments c
              where c.id = comment_id and public.can_see_task(c.task_id, auth.uid())));
  create policy "comment attachments insert in scope" on public.task_comment_attachments
    for insert to authenticated with check (
      exists (select 1 from public.task_comments c
              where c.id = comment_id and public.can_see_task(c.task_id, auth.uid())));

  -- task_activities (new table)
  alter table public.task_activities enable row level security;
  drop policy if exists "activities readable in scope" on public.task_activities;
  drop policy if exists "activities insert in scope" on public.task_activities;
  create policy "activities readable in scope" on public.task_activities
    for select to authenticated using (public.can_see_task(task_id, auth.uid()));
  create policy "activities insert in scope" on public.task_activities
    for insert to authenticated with check (public.can_see_task(task_id, auth.uid()));
end $$;
