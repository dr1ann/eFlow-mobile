-- Planning controls: acceptance criteria, dependencies, cancellation, and
-- idempotent due/review reminders. Existing task rows remain valid.

alter table public.tasks
  add column if not exists acceptance_criteria jsonb not null default '[]'::jsonb,
  add column if not exists definition_of_done text,
  add column if not exists dependency_ids uuid[] not null default '{}'::uuid[],
  add column if not exists cancellation_reason text,
  add column if not exists cancelled_at timestamptz,
  add column if not exists cancelled_by uuid references public.profiles(id) on delete set null;

alter table public.tasks drop constraint if exists tasks_status_check;
alter table public.tasks add constraint tasks_status_check check (
  status in (
    'pending_assignment', 'todo', 'in_progress', 'for_review',
    'changes_requested', 'completed', 'cancelled'
  )
);

alter table public.tasks drop constraint if exists tasks_assignment_consistent;
alter table public.tasks add constraint tasks_assignment_consistent check (
  (status = 'pending_assignment' and assigned_to is null)
  or status in (
    'todo', 'in_progress', 'for_review', 'changes_requested',
    'completed', 'cancelled'
  )
);

alter table public.tasks drop constraint if exists tasks_no_self_dependency;
alter table public.tasks add constraint tasks_no_self_dependency check (
  not (id = any(dependency_ids))
);

create index if not exists tasks_dependency_ids_idx
  on public.tasks using gin(dependency_ids);

create or replace function public.guard_task_submission_readiness()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  unresolved_count int;
begin
  if new.status = 'for_review' and old.status is distinct from 'for_review' then
    select count(*) into unresolved_count
    from unnest(new.dependency_ids) dependency_id
    left join public.tasks dependency on dependency.id = dependency_id
    where dependency.id is null
       or dependency.deleted_at is not null
       or dependency.status <> 'completed';

    if unresolved_count > 0 then
      raise exception 'Complete all task dependencies before submitting for review'
        using errcode = '22023';
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists tasks_guard_submission_readiness on public.tasks;
create trigger tasks_guard_submission_readiness
before update of status on public.tasks
for each row execute function public.guard_task_submission_readiness();

create or replace function public.cancel_task(
  p_task_id uuid,
  p_reason text
)
returns public.tasks
language plpgsql
security definer
set search_path = public
as $$
declare
  caller uuid := auth.uid();
  caller_name text;
  t public.tasks;
  previous_status text;
begin
  if caller is null then
    raise exception 'Not authenticated' using errcode = '42501';
  end if;
  if coalesce(btrim(p_reason), '') = '' then
    raise exception 'A cancellation reason is required' using errcode = '22023';
  end if;

  select full_name into caller_name
  from public.profiles where id = caller;
  select * into t from public.tasks
  where id = p_task_id and deleted_at is null
  for update;
  if not found then raise exception 'Task not found'; end if;
  previous_status := t.status;
  if t.status in ('completed', 'cancelled') then
    raise exception 'Completed or cancelled tasks cannot be cancelled'
      using errcode = '22023';
  end if;
  if not public.can_manage_task(p_task_id, caller) then
    raise exception 'Not allowed to cancel this task' using errcode = '42501';
  end if;

  perform set_config('eflow.allow_status_write', 'on', true);
  update public.tasks
  set status = 'cancelled',
      cancellation_reason = btrim(p_reason),
      cancelled_at = now(),
      cancelled_by = caller,
      last_activity_at = now()
  where id = p_task_id
  returning * into t;
  perform set_config('eflow.allow_status_write', 'off', true);

  insert into public.task_status_history (
    task_id, from_status, to_status, actor_id, actor_name, note
  ) values (
    p_task_id, previous_status, 'cancelled', caller,
    coalesce(caller_name, 'Manager'), btrim(p_reason)
  );

  insert into public.task_activities (
    task_id, type, content, actor_id, actor_name
  ) values (
    p_task_id, 'cancelled', btrim(p_reason), caller,
    coalesce(caller_name, 'Manager')
  );

  insert into public.audit_events (
    actor_id, actor_name, entity_type, entity_id, action,
    reason, before_data, after_data, org_id
  ) values (
    caller, coalesce(caller_name, 'Manager'), 'task', p_task_id::text,
    'task.cancelled', btrim(p_reason),
    jsonb_build_object('status', previous_status),
    jsonb_build_object('status', 'cancelled'), t.org_id
  );

  insert into public.notifications (
    user_id, type, title, message, task_id, task_title,
    actor_id, actor_name, status_from, status_to, reason
  )
  select recipient, 'status_change', 'Task cancelled',
    '"' || t.title || '" was cancelled.', p_task_id, t.title,
    caller, coalesce(caller_name, 'Manager'), previous_status,
    'cancelled', btrim(p_reason)
  from (
    select distinct recipient from unnest(
      array_remove(array[t.assigned_to, t.reviewer_id, t.backup_reviewer_id], null)
    ) recipient
  ) recipients
  where recipient <> caller;

  return t;
end;
$$;

create table if not exists public.task_reminders (
  id uuid primary key default gen_random_uuid(),
  task_id uuid not null references public.tasks(id) on delete cascade,
  recipient_id uuid not null references public.profiles(id) on delete cascade,
  reminder_kind text not null check (
    reminder_kind in ('due_soon', 'overdue', 'overdue_escalation', 'review_waiting')
  ),
  reminder_date date not null default current_date,
  created_at timestamptz not null default now(),
  unique (task_id, recipient_id, reminder_kind, reminder_date)
);

alter table public.task_reminders enable row level security;
drop policy if exists task_reminders_read_own on public.task_reminders;
create policy task_reminders_read_own on public.task_reminders
  for select to authenticated using (recipient_id = auth.uid());

create or replace function public.dispatch_task_reminders()
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  inserted_count int := 0;
begin
  with candidates as (
    select
      t.id as task_id,
      t.title,
      t.assigned_to as recipient_id,
      case
        when (case when t.due_date ~ '^\d{4}-\d{2}-\d{2}$' then t.due_date::date end) < current_date then 'overdue'
        else 'due_soon'
      end as reminder_kind,
      (case when t.due_date ~ '^\d{4}-\d{2}-\d{2}$' then t.due_date::date end) as due_on
    from public.tasks t
    where t.deleted_at is null
      and t.archived_at is null
      and t.status not in ('completed', 'cancelled')
      and t.assigned_to is not null
      and t.due_date ~ '^\d{4}-\d{2}-\d{2}$'
      and (case when t.due_date ~ '^\d{4}-\d{2}-\d{2}$' then t.due_date::date end) <= current_date + 2
    union all
    select
      t.id,
      t.title,
      coalesce(t.reviewer_id, t.backup_reviewer_id),
      'review_waiting',
      current_date
    from public.tasks t
    where t.deleted_at is null
      and t.archived_at is null
      and t.status = 'for_review'
      and t.updated_at < now() - interval '24 hours'
      and coalesce(t.reviewer_id, t.backup_reviewer_id) is not null
    union all
    select
      t.id,
      t.title,
      coalesce(t.reviewer_id, t.created_by),
      'overdue_escalation',
      (case when t.due_date ~ '^\d{4}-\d{2}-\d{2}$' then t.due_date::date end)
    from public.tasks t
    where t.deleted_at is null
      and t.archived_at is null
      and t.status not in ('completed', 'cancelled')
      and t.due_date ~ '^\d{4}-\d{2}-\d{2}$'
      and (case when t.due_date ~ '^\d{4}-\d{2}-\d{2}$' then t.due_date::date end) <= current_date - 3
      and coalesce(t.reviewer_id, t.created_by) is not null
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
    select
      i.recipient_id,
      'reminder',
      case i.reminder_kind
        when 'due_soon' then 'Task due soon'
        when 'overdue' then 'Task overdue'
        when 'overdue_escalation' then 'Overdue task escalation'
        else 'Review waiting'
      end,
      case i.reminder_kind
        when 'due_soon' then '"' || t.title || '" is due within two days.'
        when 'overdue' then '"' || t.title || '" is overdue.'
        when 'overdue_escalation' then '"' || t.title || '" is more than three days overdue.'
        else '"' || t.title || '" has been waiting for review for over 24 hours.'
      end,
      t.id,
      t.title
    from inserted i
    join public.tasks t on t.id = i.task_id
    returning 1
  )
  select count(*) into inserted_count from notifications_inserted;

  return inserted_count;
end;
$$;

revoke all on function public.cancel_task(uuid, text) from public, anon;
revoke all on function public.dispatch_task_reminders() from public, anon;
grant execute on function public.cancel_task(uuid, text) to authenticated;
grant execute on function public.dispatch_task_reminders() to authenticated;
grant select on table public.task_reminders to authenticated;
