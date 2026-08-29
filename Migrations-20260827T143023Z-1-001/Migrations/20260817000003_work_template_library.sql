-- Governed work-template library:
-- 1) recurring whole-task schedules are available to scoped Team Leaders;
-- 2) reusable subtask checklists support personal/department visibility;
-- 3) applying a checklist is atomic and cannot replace started work.

create or replace function public.can_use_work_templates(
  target_org uuid,
  caller_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.profiles p
    where p.id = caller_id
      and p.is_active
      and (
        p.role::text = 'super_admin'
        or (
          p.org_id = target_org
          and (
            p.role::text in ('dept_head', 'department_head', 'assistant_head')
            or exists (
              select 1
              from public.tasks t
              where t.org_id = target_org
                and t.deleted_at is null
                and (
                  t.recommendation_lead_id = caller_id
                  or (t.recommendation_lead_id is null and t.assigned_to = caller_id)
                )
            )
          )
        )
      )
  );
$$;

create or replace function public.can_approve_work_templates(
  target_org uuid,
  caller_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.profiles p
    where p.id = caller_id
      and p.is_active
      and (
        p.role::text = 'super_admin'
        or (
          p.org_id = target_org
          and p.role::text in ('dept_head', 'department_head', 'assistant_head')
        )
      )
  );
$$;

-- Team Leaders own their recurring schedules. Heads and Assistant Heads can
-- inspect and manage every recurring schedule in their direct department.
drop policy if exists task_templates_read on public.task_templates;
drop policy if exists task_templates_insert on public.task_templates;
drop policy if exists task_templates_update on public.task_templates;
drop policy if exists task_templates_delete on public.task_templates;

create policy task_templates_read on public.task_templates
  for select to authenticated using (
    created_by = auth.uid()
    or public.can_approve_work_templates(org_id, auth.uid())
  );

create policy task_templates_insert on public.task_templates
  for insert to authenticated with check (
    created_by = auth.uid()
    and public.can_use_work_templates(org_id, auth.uid())
  );

create policy task_templates_update on public.task_templates
  for update to authenticated
  using (
    created_by = auth.uid()
    or public.can_approve_work_templates(org_id, auth.uid())
  )
  with check (
    created_by = auth.uid()
    or public.can_approve_work_templates(org_id, auth.uid())
  );

create policy task_templates_delete on public.task_templates
  for delete to authenticated using (
    created_by = auth.uid()
    or public.can_approve_work_templates(org_id, auth.uid())
  );

create or replace function public.guard_recurring_template_scope()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.assignee_id is not null and not exists (
    select 1 from public.profiles p
    where p.id = new.assignee_id and p.is_active and p.org_id = new.org_id
  ) then
    raise exception 'Recurring-task assignee must be an active member directly assigned to this department'
      using errcode = '42501';
  end if;
  if new.reviewer_id is not null and not exists (
    select 1 from public.profiles p
    where p.id = new.reviewer_id and p.is_active and p.org_id = new.org_id
  ) then
    raise exception 'Recurring-task reviewer must be an active member directly assigned to this department'
      using errcode = '42501';
  end if;
  return new;
end;
$$;

drop trigger if exists task_templates_guard_scope on public.task_templates;
create trigger task_templates_guard_scope
before insert or update of org_id, assignee_id, reviewer_id
on public.task_templates
for each row execute function public.guard_recurring_template_scope();

create table if not exists public.subtask_templates (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organizations(id) on delete cascade,
  owner_id uuid references public.profiles(id) on delete set null,
  owner_name text,
  title text not null check (btrim(title) <> ''),
  description text not null default '',
  visibility text not null default 'personal'
    check (visibility in ('personal', 'department')),
  approval_status text not null default 'approved'
    check (approval_status in ('pending', 'approved', 'rejected')),
  is_starter boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.subtask_template_items (
  id uuid primary key default gen_random_uuid(),
  template_id uuid not null references public.subtask_templates(id) on delete cascade,
  title text not null check (btrim(title) <> ''),
  position int not null default 0 check (position >= 0),
  created_at timestamptz not null default now()
);

create index if not exists subtask_templates_org_visibility_idx
  on public.subtask_templates(org_id, visibility, approval_status);
create index if not exists subtask_templates_owner_idx
  on public.subtask_templates(owner_id);
create index if not exists subtask_template_items_order_idx
  on public.subtask_template_items(template_id, position);

drop trigger if exists subtask_templates_touch on public.subtask_templates;
create trigger subtask_templates_touch
before update on public.subtask_templates
for each row execute function public.touch_updated_at();

create or replace function public.guard_subtask_template_governance()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  caller uuid := auth.uid();
begin
  -- Privileged migrations seed starter templates without a JWT. Anonymous
  -- clients still cannot write because RLS rejects their table operation.
  if caller is null then return new; end if;

  if tg_op = 'INSERT' then
    if new.owner_id is null then new.owner_id := caller; end if;
    if new.owner_id <> caller and not public.can_approve_work_templates(new.org_id, caller) then
      raise exception 'Template ownership cannot be assigned to another user'
        using errcode = '42501';
    end if;
    new.approval_status := case
      when new.visibility = 'personal' then 'approved'
      when public.can_approve_work_templates(new.org_id, caller) then 'approved'
      else 'pending'
    end;
    return new;
  end if;

  if new.org_id is distinct from old.org_id
     or new.owner_id is distinct from old.owner_id
     or new.is_starter is distinct from old.is_starter then
    raise exception 'Template organization, ownership, and starter status are immutable'
      using errcode = '42501';
  end if;

  if not public.can_approve_work_templates(new.org_id, caller) then
    if new.approval_status is distinct from old.approval_status then
      raise exception 'Only a Head or Assistant Head may decide department template approval'
        using errcode = '42501';
    end if;
    new.approval_status := case
      when new.visibility = 'personal' then 'approved'
      when new.title is distinct from old.title
        or new.description is distinct from old.description
        or new.visibility is distinct from old.visibility then 'pending'
      else old.approval_status
    end;
  elsif new.visibility = 'personal' then
    new.approval_status := 'approved';
  end if;

  return new;
end;
$$;

drop trigger if exists subtask_templates_governance on public.subtask_templates;
create trigger subtask_templates_governance
before insert or update on public.subtask_templates
for each row execute function public.guard_subtask_template_governance();

alter table public.subtask_templates enable row level security;
alter table public.subtask_template_items enable row level security;

drop policy if exists subtask_templates_read on public.subtask_templates;
drop policy if exists subtask_templates_insert on public.subtask_templates;
drop policy if exists subtask_templates_update on public.subtask_templates;
drop policy if exists subtask_templates_delete on public.subtask_templates;

create policy subtask_templates_read on public.subtask_templates
  for select to authenticated using (
    owner_id = auth.uid()
    or (
      visibility = 'department'
      and public.can_approve_work_templates(org_id, auth.uid())
    )
    or (
      visibility = 'department'
      and approval_status = 'approved'
      and exists (
        select 1 from public.profiles p
        where p.id = auth.uid() and p.is_active and p.org_id = org_id
      )
    )
  );

create policy subtask_templates_insert on public.subtask_templates
  for insert to authenticated with check (
    owner_id = auth.uid()
    and public.can_use_work_templates(org_id, auth.uid())
  );

create policy subtask_templates_update on public.subtask_templates
  for update to authenticated
  using (
    owner_id = auth.uid()
    or (
      visibility = 'department'
      and public.can_approve_work_templates(org_id, auth.uid())
    )
  )
  with check (
    owner_id = auth.uid()
    or (
      visibility = 'department'
      and public.can_approve_work_templates(org_id, auth.uid())
    )
  );

create policy subtask_templates_delete on public.subtask_templates
  for delete to authenticated using (
    owner_id = auth.uid()
    or (
      visibility = 'department'
      and public.can_approve_work_templates(org_id, auth.uid())
    )
  );

drop policy if exists subtask_template_items_read on public.subtask_template_items;
create policy subtask_template_items_read on public.subtask_template_items
  for select to authenticated using (
    exists (
      select 1 from public.subtask_templates template
      where template.id = template_id
        and (
          template.owner_id = auth.uid()
          or (
            template.visibility = 'department'
            and public.can_approve_work_templates(template.org_id, auth.uid())
          )
          or (
            template.visibility = 'department'
            and template.approval_status = 'approved'
            and exists (
              select 1 from public.profiles p
              where p.id = auth.uid() and p.is_active and p.org_id = template.org_id
            )
          )
        )
    )
  );

create or replace function public.save_subtask_template(
  p_template_id uuid,
  p_payload jsonb
)
returns public.subtask_templates
language plpgsql
security definer
set search_path = public
as $$
declare
  caller uuid := auth.uid();
  caller_name text;
  target_org uuid;
  template_row public.subtask_templates;
  item jsonb;
  item_count int;
begin
  if caller is null then raise exception 'Not authenticated' using errcode = '42501'; end if;
  if btrim(coalesce(p_payload ->> 'title', '')) = '' then
    raise exception 'Template name is required' using errcode = '22023';
  end if;
  if jsonb_typeof(coalesce(p_payload -> 'items', '[]'::jsonb)) <> 'array' then
    raise exception 'Template items must be an array' using errcode = '22023';
  end if;
  item_count := jsonb_array_length(coalesce(p_payload -> 'items', '[]'::jsonb));
  if item_count = 0 then raise exception 'Add at least one subtask' using errcode = '22023'; end if;

  if p_template_id is null then
    target_org := nullif(p_payload ->> 'orgId', '')::uuid;
    if target_org is null or not public.can_use_work_templates(target_org, caller) then
      raise exception 'You may only create templates for the department where you lead work'
        using errcode = '42501';
    end if;
    select full_name into caller_name from public.profiles where id = caller;
    insert into public.subtask_templates (
      org_id, owner_id, owner_name, title, description, visibility
    ) values (
      target_org,
      caller,
      coalesce(caller_name, 'User'),
      btrim(p_payload ->> 'title'),
      btrim(coalesce(p_payload ->> 'description', '')),
      case when p_payload ->> 'visibility' = 'department' then 'department' else 'personal' end
    ) returning * into template_row;
  else
    select * into template_row
    from public.subtask_templates
    where id = p_template_id
    for update;
    if not found then raise exception 'Template not found' using errcode = 'P0002'; end if;
    if template_row.owner_id <> caller
       and not (
         template_row.visibility = 'department'
         and public.can_approve_work_templates(template_row.org_id, caller)
       ) then
      raise exception 'You cannot edit this template' using errcode = '42501';
    end if;
    update public.subtask_templates
    set
      title = btrim(p_payload ->> 'title'),
      description = btrim(coalesce(p_payload ->> 'description', '')),
      visibility = case when p_payload ->> 'visibility' = 'department' then 'department' else 'personal' end
    where id = p_template_id
    returning * into template_row;
    delete from public.subtask_template_items where template_id = p_template_id;
  end if;

  for item in select value from jsonb_array_elements(p_payload -> 'items') loop
    if btrim(coalesce(item ->> 'title', '')) = '' then
      raise exception 'Every checklist item needs a title' using errcode = '22023';
    end if;
    insert into public.subtask_template_items (template_id, title, position)
    values (
      template_row.id,
      btrim(item ->> 'title'),
      coalesce((item ->> 'position')::int, 0)
    );
  end loop;

  select * into template_row from public.subtask_templates where id = template_row.id;
  return template_row;
end;
$$;

create or replace function public.review_subtask_template(
  p_template_id uuid,
  p_approve boolean
)
returns public.subtask_templates
language plpgsql
security definer
set search_path = public
as $$
declare
  caller uuid := auth.uid();
  template_row public.subtask_templates;
begin
  select * into template_row from public.subtask_templates where id = p_template_id for update;
  if not found then raise exception 'Template not found' using errcode = 'P0002'; end if;
  if template_row.visibility <> 'department' then
    raise exception 'Personal templates do not require approval' using errcode = '22023';
  end if;
  if not public.can_approve_work_templates(template_row.org_id, caller) then
    raise exception 'Only a Head or Assistant Head may approve department templates'
      using errcode = '42501';
  end if;
  update public.subtask_templates
  set approval_status = case when p_approve then 'approved' else 'rejected' end
  where id = p_template_id
  returning * into template_row;
  return template_row;
end;
$$;

create or replace function public.apply_subtask_template(
  p_template_id uuid,
  p_task_id uuid,
  p_mode text,
  p_items jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  caller uuid := auth.uid();
  caller_name text;
  template_row public.subtask_templates;
  task_row public.tasks;
  item jsonb;
  assigned_ids uuid[];
  next_position int;
  created_count int := 0;
  skipped_count int := 0;
  replaced_count int := 0;
  item_title text;
begin
  if caller is null then raise exception 'Not authenticated' using errcode = '42501'; end if;
  if p_mode not in ('merge', 'replace') then
    raise exception 'Apply mode must be merge or replace' using errcode = '22023';
  end if;
  if jsonb_typeof(coalesce(p_items, '[]'::jsonb)) <> 'array'
     or jsonb_array_length(coalesce(p_items, '[]'::jsonb)) = 0 then
    raise exception 'Keep at least one checklist item' using errcode = '22023';
  end if;

  select * into template_row from public.subtask_templates where id = p_template_id;
  if not found then raise exception 'Template not found' using errcode = 'P0002'; end if;
  if template_row.visibility = 'personal' and template_row.owner_id <> caller then
    raise exception 'This personal template belongs to another user'
      using errcode = '42501';
  end if;
  if template_row.approval_status <> 'approved' then
    raise exception 'This department template is not approved yet' using errcode = '22023';
  end if;

  select * into task_row
  from public.tasks
  where id = p_task_id and deleted_at is null
  for update;
  if not found then raise exception 'Task not found' using errcode = 'P0002'; end if;
  if task_row.org_id is distinct from template_row.org_id then
    raise exception 'Template and task must belong to the same department'
      using errcode = '42501';
  end if;
  if task_row.archived_at is not null
     or task_row.status in ('for_review', 'completed', 'cancelled') then
    raise exception 'This task is locked and cannot receive template subtasks'
      using errcode = '22023';
  end if;
  if not public.can_manage_subtasks(p_task_id, caller) then
    raise exception 'Only the Team Lead may apply a subtask template to this task'
      using errcode = '42501';
  end if;

  if p_mode = 'replace' then
    if exists (
      select 1 from public.subtasks s
      where s.task_id = p_task_id
        and (
          s.status <> 'todo'
          or s.percent_complete > 0
          or s.is_completed
          or s.latest_submission_id is not null
        )
    ) then
      raise exception 'A subtask is already in progress or has review history and cannot be deleted or overridden'
        using errcode = '22023';
    end if;
    select count(*) into replaced_count from public.subtasks where task_id = p_task_id;
    delete from public.subtasks where task_id = p_task_id;
  end if;

  select coalesce(max(position), -1) + 1 into next_position
  from public.subtasks where task_id = p_task_id;
  select full_name into caller_name from public.profiles where id = caller;

  for item in select value from jsonb_array_elements(p_items) loop
    item_title := btrim(coalesce(item ->> 'title', ''));
    if item_title = '' then raise exception 'Every checklist item needs a title' using errcode = '22023'; end if;

    if p_mode = 'merge' and exists (
      select 1 from public.subtasks s
      where s.task_id = p_task_id and lower(btrim(s.title)) = lower(item_title)
    ) then
      skipped_count := skipped_count + 1;
      continue;
    end if;

    begin
      select coalesce(array_agg(value::uuid), '{}'::uuid[])
      into assigned_ids
      from jsonb_array_elements_text(coalesce(item -> 'assignedToIds', '[]'::jsonb));
    exception when invalid_text_representation then
      raise exception 'A selected subtask assignee is invalid' using errcode = '22023';
    end;

    if exists (
      select 1
      from unnest(assigned_ids) assigned_id
      left join public.profiles p on p.id = assigned_id
      where p.id is null or not p.is_active or p.org_id is distinct from task_row.org_id
    ) then
      raise exception 'Subtask assignees must be active members directly assigned to this department'
        using errcode = '42501';
    end if;

    insert into public.subtasks (
      task_id, title, source, position, created_by,
      assigned_to, assigned_to_ids
    ) values (
      p_task_id, item_title, 'template', next_position, caller,
      assigned_ids[1], assigned_ids
    );

    insert into public.notifications (
      user_id, type, title, message, task_id, task_title,
      actor_id, actor_name
    )
    select
      assigned_id,
      'assignment',
      'New Subtask Assignment',
      coalesce(caller_name, 'Your Team Lead') || ' assigned you to subtask "' || item_title || '" in "' || task_row.title || '".',
      task_row.id,
      task_row.title,
      caller,
      coalesce(caller_name, 'Team Lead')
    from unnest(assigned_ids) assigned_id
    where assigned_id <> caller;

    created_count := created_count + 1;
    next_position := next_position + 1;
  end loop;

  insert into public.audit_events (
    actor_id, actor_name, entity_type, entity_id, action, after_data, org_id
  ) values (
    caller,
    coalesce(caller_name, 'Team Lead'),
    'task',
    p_task_id::text,
    'subtask_template.applied',
    jsonb_build_object(
      'templateId', p_template_id,
      'mode', p_mode,
      'created', created_count,
      'skipped', skipped_count,
      'replaced', replaced_count
    ),
    task_row.org_id
  );

  return jsonb_build_object(
    'created', created_count,
    'skipped', skipped_count,
    'replaced', replaced_count
  );
end;
$$;

-- Real editable/deletable starter checklist for each organization with an
-- assigned Head or Assistant Head. Team Leaders can apply it or copy it.
insert into public.subtask_templates (
  org_id, owner_id, owner_name, title, description,
  visibility, approval_status, is_starter
)
select
  o.id,
  coalesce(o.head_user_id, o.assistant_head_user_id),
  coalesce(p.full_name, 'Department Leadership'),
  'Meeting Preparation',
  'Reusable checklist for planning, running, and documenting department meetings.',
  'department',
  'approved',
  true
from public.organizations o
join public.profiles p on p.id = coalesce(o.head_user_id, o.assistant_head_user_id)
where coalesce(o.head_user_id, o.assistant_head_user_id) is not null
  and not exists (
    select 1 from public.subtask_templates existing
    where existing.org_id = o.id and existing.is_starter
      and lower(existing.title) = 'meeting preparation'
  );

insert into public.subtask_template_items (template_id, title, position)
select template.id, item.title, item.position
from public.subtask_templates template
cross join lateral (
  values
    ('Prepare invitation and attendee list', 0),
    ('Send invitations and confirm attendance', 1),
    ('Prepare agenda and presentation', 2),
    ('Arrange venue and equipment', 3),
    ('Prepare refreshments and snacks', 4),
    ('Record minutes and action items', 5)
) as item(title, position)
where template.is_starter
  and lower(template.title) = 'meeting preparation'
  and not exists (
    select 1 from public.subtask_template_items existing_item
    where existing_item.template_id = template.id
  );

revoke all on function public.can_use_work_templates(uuid, uuid) from public, anon, authenticated;
revoke all on function public.can_approve_work_templates(uuid, uuid) from public, anon, authenticated;
revoke all on function public.guard_subtask_template_governance() from public, anon, authenticated;
revoke all on function public.guard_recurring_template_scope() from public, anon, authenticated;
revoke all on function public.save_subtask_template(uuid, jsonb) from public, anon;
revoke all on function public.review_subtask_template(uuid, boolean) from public, anon;
revoke all on function public.apply_subtask_template(uuid, uuid, text, jsonb) from public, anon;
grant execute on function public.save_subtask_template(uuid, jsonb) to authenticated;
grant execute on function public.review_subtask_template(uuid, boolean) to authenticated;
grant execute on function public.apply_subtask_template(uuid, uuid, text, jsonb) to authenticated;
grant execute on function public.can_use_work_templates(uuid, uuid) to authenticated;
grant execute on function public.can_approve_work_templates(uuid, uuid) to authenticated;
grant select, insert, update, delete on public.subtask_templates to authenticated;
grant select on public.subtask_template_items to authenticated;

-- The live tasks.team_member_ids contract is uuid[]. The original recurring
-- migration predated that normalization and attempted to insert jsonb.
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
      where template_id = template.id and scheduled_for = template.next_run_at
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
      update public.task_templates set next_run_at = next_run where id = template.id;
      continue;
    end if;

    insert into public.tasks (
      title, description, status, priority, tags,
      acceptance_criteria, definition_of_done, org_id,
      assigned_to, reviewer_id, team_member_ids,
      created_by, last_activity_at
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
        when template.assignee_id is null then '{}'::uuid[]
        else array[template.assignee_id]::uuid[]
      end,
      template.created_by,
      now()
    ) returning * into generated_task;

    insert into public.task_template_runs (template_id, task_id, scheduled_for)
    values (template.id, generated_task.id, template.next_run_at);

    if template.assignee_id is not null then
      insert into public.notifications (user_id, type, title, message, task_id, task_title)
      values (
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
