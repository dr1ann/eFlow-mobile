-- Sir Gerson updates, Phase 5: immutable, explainable monthly contribution snapshots.

create table if not exists public.monthly_productivity_snapshots (
  id uuid primary key default gen_random_uuid(),
  month_start date not null,
  user_id uuid not null references public.profiles(id) on delete restrict,
  org_id uuid references public.organizations(id) on delete set null,
  approved_tasks integer not null default 0,
  approved_subtasks integer not null default 0,
  on_time_rate numeric(6,2),
  median_cycle_hours numeric(12,2),
  first_pass_rate numeric(6,2),
  delivery_score numeric(12,2) not null default 0,
  quality_score numeric(12,2) not null default 0,
  speed_score numeric(12,2) not null default 0,
  collaboration_score numeric(12,2) not null default 0,
  contribution_score numeric(12,2) not null default 0,
  calculation_version text not null default 'v1',
  source_summary jsonb not null default '{}'::jsonb,
  generated_by uuid references public.profiles(id) on delete set null,
  generated_at timestamptz not null default now(),
  unique (month_start, user_id, org_id)
);

create index if not exists monthly_productivity_month_org_idx
  on public.monthly_productivity_snapshots(month_start desc, org_id, contribution_score desc);

alter table public.monthly_productivity_snapshots enable row level security;
drop policy if exists monthly_productivity_read on public.monthly_productivity_snapshots;
create policy monthly_productivity_read on public.monthly_productivity_snapshots
for select to authenticated using (
  public.is_super_admin(auth.uid())
  or user_id = auth.uid()
  or public.can_access_org(auth.uid(), org_id, 'read')
);

-- There is deliberately no browser INSERT/UPDATE/DELETE policy. Historical
-- rankings change only through this audited security-definer function.
drop function if exists public.recalculate_monthly_productivity(date, text);
create function public.recalculate_monthly_productivity(
  p_month_start date,
  p_reason text
)
returns setof public.monthly_productivity_snapshots
language plpgsql
security definer
set search_path = public
as $$
declare
  caller uuid := auth.uid();
  normalized_month date := date_trunc('month', p_month_start)::date;
  month_begin timestamptz;
  month_end timestamptz;
  caller_name text := '';
begin
  if caller is not null and not public.is_super_admin(caller) then
    raise exception 'Super Admin access is required' using errcode = '42501';
  end if;
  if caller is null and p_reason <> 'Scheduled month close' then
    raise exception 'A signed-in Super Admin is required for manual recalculation' using errcode = '42501';
  end if;
  if nullif(btrim(p_reason), '') is null then
    raise exception 'A recalculation reason is required' using errcode = '22023';
  end if;
  if normalized_month >= date_trunc('month', now() at time zone 'Asia/Manila')::date then
    raise exception 'Only a closed Manila calendar month can be snapshotted' using errcode = '22023';
  end if;
  month_begin := normalized_month::timestamp at time zone 'Asia/Manila';
  month_end := (normalized_month + interval '1 month')::timestamp at time zone 'Asia/Manila';
  select coalesce(full_name, '') into caller_name from public.profiles where id = caller;

  delete from public.monthly_productivity_snapshots where month_start = normalized_month;

  insert into public.monthly_productivity_snapshots (
    month_start, user_id, org_id, approved_tasks, approved_subtasks,
    on_time_rate, median_cycle_hours, first_pass_rate,
    delivery_score, quality_score, speed_score, collaboration_score,
    contribution_score, source_summary, generated_by
  )
  with approved_work as (
    select distinct on (submission.task_id)
      submission.task_id as work_id,
      'task'::text as kind,
      submission.submitter_id as user_id,
      task.org_id,
      submission.version,
      submission.submitted_at,
      submission.decided_at,
      task.created_at,
      task.priority,
      task.estimated_hours,
      case
        when task.due_date ~ '^\d{4}-\d{2}-\d{2}' then left(task.due_date, 10)::date
        when task.deadline ~ '^\d{4}-\d{2}-\d{2}' then left(task.deadline, 10)::date
      end as due_date
    from public.task_submissions submission
    join public.tasks task on task.id = submission.task_id
    where submission.status = 'approved'
      and submission.decided_at >= month_begin and submission.decided_at < month_end
      and submission.decided_by is distinct from submission.submitter_id
      and task.deleted_at is null and task.status <> 'cancelled'
      and not (task.reopened_at is not null and task.reopened_at > submission.decided_at)
    order by submission.task_id, submission.decided_at desc
  ), approved_subtask_work as (
    select distinct on (submission.subtask_id)
      submission.subtask_id as work_id,
      'subtask'::text as kind,
      submission.submitter_id as user_id,
      task.org_id,
      submission.version,
      submission.submitted_at,
      submission.decided_at,
      subtask.created_at,
      task.priority,
      null::numeric as estimated_hours,
      case
        when task.due_date ~ '^\d{4}-\d{2}-\d{2}' then left(task.due_date, 10)::date
        when task.deadline ~ '^\d{4}-\d{2}-\d{2}' then left(task.deadline, 10)::date
      end as due_date
    from public.subtask_submissions submission
    join public.subtasks subtask on subtask.id = submission.subtask_id
    join public.tasks task on task.id = submission.task_id
    where submission.status = 'approved'
      and submission.decided_at >= month_begin and submission.decided_at < month_end
      and submission.decided_by is distinct from submission.submitter_id
      and task.deleted_at is null and task.status <> 'cancelled'
    order by submission.subtask_id, submission.decided_at desc
  ), work as (
    select * from approved_work union all select * from approved_subtask_work
  ), scored as (
    select *,
      extract(epoch from (decided_at - created_at)) / 3600.0 as cycle_hours,
      (due_date is not null and (decided_at at time zone 'Asia/Manila')::date <= due_date) as on_time,
      case priority when 'high' then 2.0 when 'medium' then 1.5 else 1.0 end
        * case when kind = 'task' then least(3.0, greatest(0.75, coalesce(estimated_hours, 8) / 8.0)) else 1.0 end as effort_weight
    from work
  ), aggregate_rows as (
    select user_id, org_id,
      count(*) filter (where kind = 'task')::integer as approved_tasks,
      count(*) filter (where kind = 'subtask')::integer as approved_subtasks,
      round(100 * avg(case when on_time then 1 else 0 end), 2) as on_time_rate,
      round((percentile_cont(0.5) within group (order by cycle_hours))::numeric, 2) as median_cycle_hours,
      round(100 * avg(case when version = 1 then 1 else 0 end), 2) as first_pass_rate,
      round(sum(case when kind = 'task' then effort_weight * 10 else 0 end), 2) as delivery_score,
      round((avg(case when on_time then 1 else 0 end) * 10 + avg(case when version = 1 then 1 else 0 end) * 10)::numeric, 2) as quality_score,
      round(least(10, coalesce(
        avg(case when cycle_hours <= estimated_hours * 2 then 10 else 0 end)
          filter (where kind = 'task' and estimated_hours is not null),
        0
      ))::numeric, 2) as speed_score,
      least(30, count(*) filter (where kind = 'subtask') * 3)::numeric as collaboration_score
    from scored group by user_id, org_id
  )
  select normalized_month, user_id, org_id, approved_tasks, approved_subtasks,
    on_time_rate, median_cycle_hours, first_pass_rate,
    delivery_score, quality_score, speed_score, collaboration_score,
    round(delivery_score + quality_score + speed_score + collaboration_score, 2),
    jsonb_build_object('timezone', 'Asia/Manila', 'calculation_version', 'v1', 'reason', p_reason), caller
  from aggregate_rows;

  insert into public.audit_events (
    actor_id, actor_name, entity_type, entity_id, action, reason, after_data
  ) values (
    caller, caller_name, 'monthly_productivity_snapshot', normalized_month::text,
    'productivity.snapshot_recalculated', btrim(p_reason),
    jsonb_build_object('month_start', normalized_month, 'timezone', 'Asia/Manila', 'calculation_version', 'v1')
  );

  return query select * from public.monthly_productivity_snapshots
  where month_start = normalized_month order by contribution_score desc, user_id;
end;
$$;

revoke all on function public.recalculate_monthly_productivity(date, text) from public, anon;
grant execute on function public.recalculate_monthly_productivity(date, text) to authenticated;

-- Supabase projects with pg_cron enabled close the previous Manila month
-- automatically. Projects without pg_cron keep the audited manual RPC.
do $schedule$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.schedule(
      'eflow-monthly-productivity-snapshot',
      '10 16 1 * *',
      'select public.recalculate_monthly_productivity((date_trunc(''month'', now() at time zone ''Asia/Manila'')::date - interval ''1 month'')::date, ''Scheduled month close'');'
    );
  end if;
end;
$schedule$;
