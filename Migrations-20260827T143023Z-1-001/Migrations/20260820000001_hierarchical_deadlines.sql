-- Hierarchical deadline controls and deduplicated warnings.
-- Subtask dates are explicit; project dates remain authoritative; proposal
-- dates are derived from the latest project target in the proposal.

alter table public.subtasks
  add column if not exists due_date date,
  add column if not exists due_date_change_reason text,
  add column if not exists due_date_changed_at timestamptz,
  add column if not exists due_date_changed_by uuid references public.profiles(id) on delete set null;

alter table public.notifications
  add column if not exists project_id uuid references public.projects(id) on delete set null,
  add column if not exists proposal_id text,
  add column if not exists org_id uuid references public.organizations(id) on delete set null,
  add column if not exists entity_type text;

create index if not exists subtasks_due_date_idx
  on public.subtasks(due_date)
  where due_date is not null and is_completed = false;
create index if not exists notifications_project_idx
  on public.notifications(project_id, created_at desc)
  where project_id is not null;

-- Give active historical subtasks a sensible first deadline when their parent
-- task already has a measurable ISO date. Leads can refine it afterward.
do $$
begin
  perform set_config('eflow.subtask_workflow_authorized', 'on', true);
  update public.subtasks subtask
  set due_date = case
    when task.due_date ~ '^\d{4}-\d{2}-\d{2}' then left(task.due_date, 10)::date
    when task.deadline ~ '^\d{4}-\d{2}-\d{2}' then left(task.deadline, 10)::date
    else null
  end
  from public.tasks task
  where task.id = subtask.task_id
    and subtask.due_date is null
    and task.deleted_at is null
    and task.status not in ('for_review', 'completed');
  perform set_config('eflow.subtask_workflow_authorized', 'off', true);
end;
$$;

create or replace function public.guard_subtask_due_date_bounds()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  parent_due date;
begin
  select case
    when task.due_date ~ '^\d{4}-\d{2}-\d{2}' then left(task.due_date, 10)::date
    when task.deadline ~ '^\d{4}-\d{2}-\d{2}' then left(task.deadline, 10)::date
    else null
  end
  into parent_due
  from public.tasks task
  where task.id = new.task_id and task.deleted_at is null;

  if tg_op = 'INSERT' and new.due_date is null then
    new.due_date := parent_due;
  end if;
  if new.due_date is null then return new; end if;

  if parent_due is not null and new.due_date > parent_due then
    raise exception 'Subtask due date cannot be later than its parent task due date (%)', parent_due
      using errcode = '22023';
  end if;
  return new;
end;
$$;

create or replace function public.guard_subtask_due_date_update()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.due_date is distinct from old.due_date
     or new.due_date_change_reason is distinct from old.due_date_change_reason
     or new.due_date_changed_at is distinct from old.due_date_changed_at
     or new.due_date_changed_by is distinct from old.due_date_changed_by then
    if coalesce(current_setting('eflow.subtask_deadline_authorized', true), 'off') <> 'on' then
      raise exception 'Use the managed subtask deadline action to change a due date'
        using errcode = '42501';
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists subtasks_guard_due_date_bounds on public.subtasks;
create trigger subtasks_guard_due_date_bounds
before insert or update of due_date on public.subtasks
for each row execute function public.guard_subtask_due_date_bounds();

drop trigger if exists subtasks_guard_due_date_update on public.subtasks;
create trigger subtasks_guard_due_date_update
before update of due_date, due_date_change_reason, due_date_changed_at, due_date_changed_by on public.subtasks
for each row execute function public.guard_subtask_due_date_update();

create or replace function public.set_subtask_due_date(
  p_subtask_id uuid,
  p_due_date date,
  p_reason text default null
)
returns public.subtasks
language plpgsql
security definer
set search_path = public
as $$
declare
  caller uuid := auth.uid();
  caller_name text := '';
  subtask public.subtasks;
  parent_task public.tasks;
  reason_required boolean;
  previous_due date;
begin
  if caller is null then
    raise exception 'Not authenticated' using errcode = '42501';
  end if;

  select * into subtask
  from public.subtasks
  where id = p_subtask_id
  for update;
  if not found then raise exception 'Subtask not found' using errcode = 'P0002'; end if;

  select * into parent_task
  from public.tasks
  where id = subtask.task_id and deleted_at is null
  for update;
  if not found then raise exception 'Parent task not found' using errcode = 'P0002'; end if;

  if not public.can_manage_subtasks(subtask.task_id, caller) then
    raise exception 'Only the Task Lead or an authorized manager may change a subtask deadline'
      using errcode = '42501';
  end if;
  if public.auth_role(caller) = 'super_admin' then
    raise exception 'Super Admin task oversight is read-only' using errcode = '42501';
  end if;
  if parent_task.archived_at is not null
     or parent_task.status in ('for_review', 'completed', 'cancelled') then
    raise exception 'Subtask deadlines are locked while the parent task is under review, completed, cancelled, or archived'
      using errcode = '22023';
  end if;
  if p_due_date is null then
    raise exception 'A subtask due date is required' using errcode = '22023';
  end if;
  if p_due_date is not null and (
    (parent_task.due_date ~ '^\d{4}-\d{2}-\d{2}' and p_due_date > left(parent_task.due_date, 10)::date)
    or (not coalesce(parent_task.due_date ~ '^\d{4}-\d{2}-\d{2}', false) and coalesce(parent_task.deadline ~ '^\d{4}-\d{2}-\d{2}', false) and p_due_date > left(parent_task.deadline, 10)::date)
  ) then
    raise exception 'Subtask due date cannot be later than its parent task due date'
      using errcode = '22023';
  end if;

  if subtask.due_date is not distinct from p_due_date then return subtask; end if;
  previous_due := subtask.due_date;
  reason_required := subtask.status <> 'todo' or subtask.percent_complete > 0;
  if reason_required and coalesce(btrim(p_reason), '') = '' then
    raise exception 'A reason is required after subtask work has started'
      using errcode = '22023';
  end if;

  select coalesce(full_name, 'Task Lead') into caller_name
  from public.profiles where id = caller;

  perform set_config('eflow.subtask_deadline_authorized', 'on', true);
  update public.subtasks
  set due_date = p_due_date,
      due_date_change_reason = nullif(btrim(p_reason), ''),
      due_date_changed_at = now(),
      due_date_changed_by = caller,
      updated_at = now()
  where id = p_subtask_id
  returning * into subtask;
  perform set_config('eflow.subtask_deadline_authorized', 'off', true);

  insert into public.audit_events (
    actor_id, actor_name, entity_type, entity_id, action, reason,
    before_data, after_data, org_id
  ) values (
    caller, caller_name, 'subtask', subtask.id::text, 'subtask.deadline.updated',
    nullif(btrim(p_reason), ''),
    jsonb_build_object('dueDate', previous_due),
    jsonb_build_object('dueDate', p_due_date), parent_task.org_id
  );

  insert into public.notifications (
    user_id, type, title, message, task_id, task_title, actor_id, actor_name,
    reason, project_id, proposal_id, org_id, entity_type
  )
  select recipient_id, 'status_change', 'Subtask deadline updated',
    caller_name || ' changed the deadline for "' || subtask.title || '" to ' || coalesce(to_char(p_due_date, 'Mon DD, YYYY'), 'No deadline') || '.',
    parent_task.id, parent_task.title, caller, caller_name,
    nullif(btrim(p_reason), ''), parent_task.linked_project_id,
    parent_task.proposal_id, parent_task.org_id, 'subtask'
  from (
    select distinct recipient_id
    from unnest(
      coalesce(subtask.assigned_to_ids, '{}'::uuid[])
      || array_remove(array[subtask.assigned_to], null)
    ) recipient_id
  ) recipients
  where recipient_id <> caller;

  return subtask;
exception when others then
  perform set_config('eflow.subtask_deadline_authorized', 'off', true);
  raise;
end;
$$;

create table if not exists public.hierarchy_deadline_reminders (
  id uuid primary key default gen_random_uuid(),
  entity_type text not null check (entity_type in ('subtask', 'task', 'project', 'proposal')),
  entity_key text not null,
  recipient_id uuid not null references public.profiles(id) on delete cascade,
  reminder_kind text not null check (reminder_kind in ('due_soon', 'overdue', 'completion_recommended')),
  due_on date not null,
  created_at timestamptz not null default now(),
  unique (entity_type, entity_key, recipient_id, reminder_kind, due_on)
);

alter table public.hierarchy_deadline_reminders enable row level security;
drop policy if exists hierarchy_deadline_reminders_read_own on public.hierarchy_deadline_reminders;
create policy hierarchy_deadline_reminders_read_own on public.hierarchy_deadline_reminders
  for select to authenticated using (recipient_id = auth.uid());

create or replace function public.dispatch_hierarchy_deadline_reminders()
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  inserted_count int := 0;
begin
  with task_dates as (
    select task.*,
      case
        when task.due_date ~ '^\d{4}-\d{2}-\d{2}' then left(task.due_date, 10)::date
        when task.deadline ~ '^\d{4}-\d{2}-\d{2}' then left(task.deadline, 10)::date
        else null
      end as due_on
    from public.tasks task
    where task.deleted_at is null and task.archived_at is null
  ), proposal_dates as (
    select project.org_id, project.proposal_id,
      max(project.proposal_title) as title,
      max(project.target_date) as due_on,
      bool_or(project.status not in ('completed', 'archived')) as incomplete
    from public.projects project
    where project.proposal_id is not null and project.status <> 'archived'
    group by project.org_id, project.proposal_id
  ), deadline_candidates as (
    select 'subtask'::text as entity_type, subtask.id::text as entity_key,
      subtask.title as entity_title, subtask.due_date as due_on,
      recipient.recipient_id, case when subtask.due_date < current_date then 'overdue' else 'due_soon' end as reminder_kind,
      task.id as task_id, task.title as task_title, task.linked_project_id as project_id,
      task.proposal_id, task.org_id
    from public.subtasks subtask
    join task_dates task on task.id = subtask.task_id
    cross join lateral (
      select distinct recipient_id from unnest(
        coalesce(subtask.assigned_to_ids, '{}'::uuid[])
        || array_remove(array[subtask.assigned_to, task.recommendation_lead_id], null)
      ) recipient_id
    ) recipient
    where subtask.is_completed = false
      and subtask.status not in ('completed', 'for_review')
      and subtask.due_date is not null
      and subtask.due_date <= current_date + 3

    union all

    select 'task', task.id::text, task.title, task.due_on,
      recipient.recipient_id, case when task.due_on < current_date then 'overdue' else 'due_soon' end,
      task.id, task.title, task.linked_project_id, task.proposal_id, task.org_id
    from task_dates task
    left join public.organizations org on org.id = task.org_id
    cross join lateral (
      select distinct recipient_id from unnest(
        coalesce(task.team_member_ids, '{}'::uuid[])
        || array_remove(array[task.assigned_to, task.recommendation_lead_id, org.head_user_id, org.assistant_head_user_id], null)
      ) recipient_id
    ) recipient
    where task.status not in ('completed', 'cancelled')
      and task.due_on is not null and task.due_on <= current_date + 3

    union all

    select 'project', project.id::text, project.title, project.target_date,
      recipient.recipient_id, case when project.target_date < current_date then 'overdue' else 'due_soon' end,
      null::uuid, null::text, project.id, project.proposal_id, project.org_id
    from public.projects project
    left join public.organizations org on org.id = project.org_id
    cross join lateral (
      select distinct recipient_id from unnest(
        array_remove(array[project.owner_id, org.head_user_id, org.assistant_head_user_id], null)
      ) recipient_id
    ) recipient
    where project.status not in ('completed', 'archived')
      and project.target_date is not null and project.target_date <= current_date + 3

    union all

    select 'proposal', proposal.org_id::text || ':' || proposal.proposal_id,
      coalesce(proposal.title, 'Proposal'), proposal.due_on,
      recipient.recipient_id, case when proposal.due_on < current_date then 'overdue' else 'due_soon' end,
      null::uuid, null::text, null::uuid, proposal.proposal_id, proposal.org_id
    from proposal_dates proposal
    join public.organizations org on org.id = proposal.org_id
    cross join lateral (
      select distinct recipient_id from unnest(
        array_remove(array[org.head_user_id, org.assistant_head_user_id], null)
      ) recipient_id
    ) recipient
    where proposal.incomplete and proposal.due_on is not null and proposal.due_on <= current_date + 3
  ), completion_candidates as (
    select 'project'::text as entity_type, project.id::text as entity_key,
      project.title as entity_title, coalesce(project.target_date, project.created_at::date) as due_on,
      recipient.recipient_id, 'completion_recommended'::text as reminder_kind,
      null::uuid as task_id, null::text as task_title, project.id as project_id,
      project.proposal_id, project.org_id
    from public.projects project
    left join public.organizations org on org.id = project.org_id
    cross join lateral (
      select distinct recipient_id from unnest(
        array_remove(array[project.owner_id, org.head_user_id, org.assistant_head_user_id], null)
      ) recipient_id
    ) recipient
    where project.status not in ('completed', 'archived')
      and exists (
        select 1 from public.tasks task
        where task.linked_project_id = project.id and task.deleted_at is null
          and task.archived_at is null and task.status <> 'cancelled'
      )
      and not exists (
        select 1 from public.tasks task
        where task.linked_project_id = project.id and task.deleted_at is null
          and task.archived_at is null and task.status not in ('completed', 'cancelled')
      )

    union all

    select 'proposal', project.org_id::text || ':' || project.proposal_id,
      max(project.proposal_title), coalesce(max(project.target_date), min(project.created_at)::date),
      recipient.recipient_id, 'completion_recommended',
      null::uuid, null::text, null::uuid, project.proposal_id, project.org_id
    from public.projects project
    join public.organizations org on org.id = project.org_id
    cross join lateral (
      select distinct recipient_id from unnest(
        array_remove(array[org.head_user_id, org.assistant_head_user_id], null)
      ) recipient_id
    ) recipient
    where project.proposal_id is not null and project.status <> 'archived'
      and exists (select 1 from public.projects incomplete where incomplete.org_id = project.org_id and incomplete.proposal_id = project.proposal_id and incomplete.status <> 'completed')
      and not exists (
        select 1
        from public.projects child
        where child.org_id = project.org_id and child.proposal_id = project.proposal_id and child.status <> 'archived'
          and (
            not exists (select 1 from public.tasks task where task.linked_project_id = child.id and task.deleted_at is null and task.archived_at is null and task.status <> 'cancelled')
            or exists (select 1 from public.tasks task where task.linked_project_id = child.id and task.deleted_at is null and task.archived_at is null and task.status not in ('completed', 'cancelled'))
          )
      )
    group by project.org_id, project.proposal_id, recipient.recipient_id
  ), candidates as (
    select distinct * from deadline_candidates
    union
    select distinct * from completion_candidates
  ), inserted as (
    insert into public.hierarchy_deadline_reminders (
      entity_type, entity_key, recipient_id, reminder_kind, due_on
    )
    select entity_type, entity_key, recipient_id, reminder_kind, due_on
    from candidates
    on conflict do nothing
    returning entity_type, entity_key, recipient_id, reminder_kind, due_on
  ), notifications_inserted as (
    insert into public.notifications (
      user_id, type, title, message, task_id, task_title,
      status_to, reason, project_id, proposal_id, org_id, entity_type
    )
    select inserted.recipient_id,
      case when inserted.reminder_kind = 'completion_recommended' then 'status_change' else 'overdue' end,
      case
        when inserted.reminder_kind = 'completion_recommended' then initcap(inserted.entity_type) || ' ready to complete'
        when inserted.reminder_kind = 'overdue' then initcap(inserted.entity_type) || ' overdue'
        else initcap(inserted.entity_type) || ' due soon'
      end,
      case
        when inserted.reminder_kind = 'completion_recommended' then 'All delivery work for "' || candidate.entity_title || '" is approved. Review and mark it completed.'
        when inserted.reminder_kind = 'overdue' then '"' || candidate.entity_title || '" passed its target date on ' || to_char(inserted.due_on, 'Mon DD, YYYY') || ' and is not completed.'
        else '"' || candidate.entity_title || '" is due on ' || to_char(inserted.due_on, 'Mon DD, YYYY') || '.'
      end,
      candidate.task_id, candidate.task_title,
      case when inserted.reminder_kind = 'completion_recommended' then 'completion_recommended' else null end,
      'Target date: ' || to_char(inserted.due_on, 'Mon DD, YYYY'),
      candidate.project_id, candidate.proposal_id, candidate.org_id, inserted.entity_type
    from inserted
    join candidates candidate
      on candidate.entity_type = inserted.entity_type
      and candidate.entity_key = inserted.entity_key
      and candidate.recipient_id = inserted.recipient_id
      and candidate.reminder_kind = inserted.reminder_kind
      and candidate.due_on = inserted.due_on
    returning 1
  )
  select count(*) into inserted_count from notifications_inserted;

  return inserted_count;
end;
$$;

-- Keep the established waiting-review and overdue-escalation reminders. The
-- hierarchy dispatcher above replaces only the old task due-soon/overdue arm.
create or replace function public.dispatch_task_review_reminders()
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  inserted_count int := 0;
begin
  with candidates as (
    select task.id as task_id, task.title,
      coalesce(task.reviewer_id, task.backup_reviewer_id) as recipient_id,
      'review_waiting'::text as reminder_kind
    from public.tasks task
    where task.deleted_at is null
      and task.archived_at is null
      and task.status = 'for_review'
      and task.updated_at < now() - interval '24 hours'
      and coalesce(task.reviewer_id, task.backup_reviewer_id) is not null

    union all

    select task.id, task.title,
      coalesce(task.reviewer_id, task.created_by),
      'overdue_escalation'
    from public.tasks task
    where task.deleted_at is null
      and task.archived_at is null
      and task.status not in ('completed', 'cancelled')
      and task.due_date ~ '^\d{4}-\d{2}-\d{2}'
      and left(task.due_date, 10)::date <= current_date - 3
      and coalesce(task.reviewer_id, task.created_by) is not null
  ), inserted as (
    insert into public.task_reminders (
      task_id, recipient_id, reminder_kind, reminder_date
    )
    select task_id, recipient_id, reminder_kind, current_date
    from candidates
    on conflict do nothing
    returning task_id, recipient_id, reminder_kind
  ), notifications_inserted as (
    insert into public.notifications (
      user_id, type, title, message, task_id, task_title
    )
    select inserted.recipient_id, 'reminder',
      case inserted.reminder_kind
        when 'overdue_escalation' then 'Overdue task escalation'
        else 'Review waiting'
      end,
      case inserted.reminder_kind
        when 'overdue_escalation' then '"' || task.title || '" is more than three days overdue.'
        else '"' || task.title || '" has been waiting for review for over 24 hours.'
      end,
      task.id, task.title
    from inserted
    join public.tasks task on task.id = inserted.task_id
    returning 1
  )
  select count(*) into inserted_count from notifications_inserted;

  return inserted_count;
end;
$$;

-- Preserve the existing public maintenance/cron contract while upgrading its
-- scope. Existing callers still invoke dispatch_task_reminders().
create or replace function public.dispatch_task_reminders()
returns int
language sql
security definer
set search_path = public
as $$
  select public.dispatch_hierarchy_deadline_reminders()
       + public.dispatch_task_review_reminders();
$$;

revoke all on function public.set_subtask_due_date(uuid, date, text) from public, anon;
revoke all on function public.dispatch_hierarchy_deadline_reminders() from public, anon;
revoke all on function public.dispatch_task_review_reminders() from public, anon;
revoke all on function public.dispatch_task_reminders() from public, anon;
grant execute on function public.set_subtask_due_date(uuid, date, text) to authenticated;
grant execute on function public.dispatch_hierarchy_deadline_reminders() to authenticated;
grant execute on function public.dispatch_task_reminders() to authenticated;
grant select on table public.hierarchy_deadline_reminders to authenticated;

notify pgrst, 'reload schema';
