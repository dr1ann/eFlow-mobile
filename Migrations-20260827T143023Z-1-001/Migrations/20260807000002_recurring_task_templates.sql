-- Reusable recurring task templates with idempotent materialization.

create table if not exists public.task_templates (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  description text not null default '',
  priority text not null default 'medium' check (priority in ('low', 'medium', 'high')),
  tags jsonb not null default '[]'::jsonb,
  acceptance_criteria jsonb not null default '[]'::jsonb,
  definition_of_done text,
  org_id uuid references public.organizations(id) on delete cascade,
  assignee_id uuid references public.profiles(id) on delete set null,
  reviewer_id uuid references public.profiles(id) on delete set null,
  recurrence_rule jsonb not null default '{"frequency":"weekly","interval":1}'::jsonb,
  next_run_at timestamptz not null,
  is_active boolean not null default true,
  created_by uuid not null references public.profiles(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check ((recurrence_rule ->> 'frequency') in ('daily', 'weekly', 'monthly')),
  check (coalesce((recurrence_rule ->> 'interval')::int, 1) between 1 and 365),
  check (assignee_id is null or reviewer_id is null or assignee_id <> reviewer_id)
);

create table if not exists public.task_template_runs (
  id uuid primary key default gen_random_uuid(),
  template_id uuid not null references public.task_templates(id) on delete cascade,
  task_id uuid references public.tasks(id) on delete set null,
  scheduled_for timestamptz not null,
  created_at timestamptz not null default now(),
  unique (template_id, scheduled_for)
);

create index if not exists task_templates_org_idx on public.task_templates(org_id);
create index if not exists task_templates_next_run_idx
  on public.task_templates(next_run_at) where is_active;

drop trigger if exists task_templates_touch on public.task_templates;
create trigger task_templates_touch before update on public.task_templates
  for each row execute function public.touch_updated_at();

alter table public.task_templates enable row level security;
alter table public.task_template_runs enable row level security;

drop policy if exists task_templates_read on public.task_templates;
drop policy if exists task_templates_insert on public.task_templates;
drop policy if exists task_templates_update on public.task_templates;
drop policy if exists task_templates_delete on public.task_templates;
create policy task_templates_read on public.task_templates
  for select to authenticated using (
    public.auth_role(auth.uid()) = 'super_admin'
    or created_by = auth.uid()
    or (
      public.auth_role(auth.uid()) in ('dept_head', 'department_head')
      and public.org_in_my_subtree(org_id, auth.uid())
    )
  );
create policy task_templates_insert on public.task_templates
  for insert to authenticated with check (
    created_by = auth.uid()
    and (
      public.auth_role(auth.uid()) = 'super_admin'
      or (
        public.auth_role(auth.uid()) in ('dept_head', 'department_head')
        and public.org_in_my_subtree(org_id, auth.uid())
      )
    )
  );
create policy task_templates_update on public.task_templates
  for update to authenticated
  using (
    public.auth_role(auth.uid()) = 'super_admin'
    or created_by = auth.uid()
  )
  with check (
    public.auth_role(auth.uid()) = 'super_admin'
    or created_by = auth.uid()
  );
create policy task_templates_delete on public.task_templates
  for delete to authenticated using (
    public.auth_role(auth.uid()) = 'super_admin'
    or created_by = auth.uid()
  );

drop policy if exists task_template_runs_read on public.task_template_runs;
create policy task_template_runs_read on public.task_template_runs
  for select to authenticated using (
    exists (
      select 1 from public.task_templates template
      where template.id = template_id
        and (
          public.auth_role(auth.uid()) = 'super_admin'
          or template.created_by = auth.uid()
          or public.org_in_my_subtree(template.org_id, auth.uid())
        )
    )
  );

create or replace function public.materialize_due_task_templates()
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  template public.task_templates;
  generated_task public.tasks;
  generated_count int := 0;
  interval_count int;
  next_run timestamptz;
begin
  for template in
    select * from public.task_templates
    where is_active and next_run_at <= now()
    order by next_run_at
    for update skip locked
  loop
    if exists (
      select 1 from public.task_template_runs
      where template_id = template.id
        and scheduled_for = template.next_run_at
    ) then
      interval_count := case
        when coalesce(template.recurrence_rule ->> 'interval', '') ~ '^\d+$'
          then greatest((template.recurrence_rule ->> 'interval')::int, 1)
        else 1
      end;
      next_run := case template.recurrence_rule ->> 'frequency'
        when 'daily' then template.next_run_at + make_interval(days => interval_count)
        when 'monthly' then template.next_run_at + make_interval(months => interval_count)
        else template.next_run_at + make_interval(weeks => interval_count)
      end;
      update public.task_templates
      set next_run_at = next_run
      where id = template.id;
      continue;
    end if;

    insert into public.tasks (
      title,
      description,
      status,
      priority,
      tags,
      acceptance_criteria,
      definition_of_done,
      org_id,
      assigned_to,
      reviewer_id,
      team_member_ids,
      created_by,
      last_activity_at
    ) values (
      template.title,
      template.description,
      case when template.assignee_id is null then 'pending_assignment' else 'todo' end,
      template.priority,
      template.tags,
      template.acceptance_criteria,
      template.definition_of_done,
      template.org_id,
      template.assignee_id,
      template.reviewer_id,
      case
        when template.assignee_id is null then '[]'::jsonb
        else jsonb_build_array(template.assignee_id::text)
      end,
      template.created_by,
      now()
    )
    returning * into generated_task;

    insert into public.task_template_runs (template_id, task_id, scheduled_for)
    values (template.id, generated_task.id, template.next_run_at);

    if template.assignee_id is not null then
      insert into public.notifications (
        user_id, type, title, message, task_id, task_title
      ) values (
        template.assignee_id,
        'assignment',
        'Recurring task assigned',
        'A recurring task was created: "' || template.title || '".',
        generated_task.id,
        template.title
      );
    end if;

    interval_count := case
      when coalesce(template.recurrence_rule ->> 'interval', '') ~ '^\d+$'
        then greatest((template.recurrence_rule ->> 'interval')::int, 1)
      else 1
    end;
    next_run := case template.recurrence_rule ->> 'frequency'
      when 'daily' then template.next_run_at + make_interval(days => interval_count)
      when 'monthly' then template.next_run_at + make_interval(months => interval_count)
      else template.next_run_at + make_interval(weeks => interval_count)
    end;

    update public.task_templates set next_run_at = next_run where id = template.id;
    generated_count := generated_count + 1;
  end loop;

  return generated_count;
end;
$$;

revoke all on function public.materialize_due_task_templates() from public, anon;
grant execute on function public.materialize_due_task_templates() to authenticated;
grant select, insert, update, delete on public.task_templates to authenticated;
grant select on public.task_template_runs to authenticated;
