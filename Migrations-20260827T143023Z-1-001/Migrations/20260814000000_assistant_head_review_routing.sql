-- Adds a generic Assistant Head position to every organization node and keeps
-- Head/Assistant Head task review reciprocal within that same organization.

-- Keep this migration rerunnable even when the deployment missed the opening
-- column step from 20260807000000_task_review_hardening.sql. The complete review
-- migration must still be applied for submissions, evidence, and decisions.
alter table public.tasks
  add column if not exists reviewer_id uuid
    references public.profiles(id) on delete set null,
  add column if not exists backup_reviewer_id uuid
    references public.profiles(id) on delete set null;

create index if not exists tasks_reviewer_idx
  on public.tasks(reviewer_id);
create index if not exists tasks_backup_reviewer_idx
  on public.tasks(backup_reviewer_id);

alter table public.organizations
  add column if not exists assistant_head_user_id uuid;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'organizations_assistant_head_user_fk'
  ) then
    alter table public.organizations
      add constraint organizations_assistant_head_user_fk
      foreign key (assistant_head_user_id)
      references public.profiles(id) on delete set null;
  end if;

  if not exists (
    select 1 from pg_constraint
    where conname = 'organizations_distinct_leadership_check'
  ) then
    alter table public.organizations
      add constraint organizations_distinct_leadership_check
      check (
        head_user_id is null
        or assistant_head_user_id is null
        or head_user_id <> assistant_head_user_id
      );
  end if;
end;
$$;

create index if not exists organizations_assistant_head_idx
  on public.organizations(assistant_head_user_id);

-- The historical schema uses this generated constraint name. Replacing it is
-- additive: existing role values remain accepted and Assistant Head is added.
alter table public.profiles drop constraint if exists profiles_role_check;
alter table public.profiles
  add constraint profiles_role_check check (role in (
    'super_admin', 'dept_head', 'assistant_head', 'employee',
    'department_head', 'executive', 'legislative', 'hrmo', 'finance',
    'councilor_pad'
  ));

-- Existing RLS and lifecycle functions already treat dept_head as the scoped
-- management role. Canonicalizing only inside this DB helper gives Assistant
-- Head identical enforcement without changing the persisted profile role.
create or replace function public.auth_role(caller_id uuid)
returns text
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  return (
    select case when role = 'assistant_head' then 'dept_head' else role::text end
    from public.profiles
    where id = caller_id
  );
end;
$$;

insert into public.role_permissions (role, permission, allowed) values
  ('assistant_head', 'projects.create', true),
  ('assistant_head', 'projects.archive', true),
  ('assistant_head', 'tasks.assign', true),
  ('assistant_head', 'tasks.verify', true),
  ('assistant_head', 'reports.export', true),
  ('assistant_head', 'announcements.publish', false),
  ('assistant_head', 'users.manage', false),
  ('assistant_head', 'audit.read', false),
  ('assistant_head', 'settings.manage', false)
on conflict (role, permission) do update
set allowed = excluded.allowed, updated_at = now();

-- Super Admin uses one transaction to assign both positions. The selected
-- profiles receive the corresponding role and organization automatically.
create or replace function public.set_organization_leadership(
  p_org_id uuid,
  p_head_user_id uuid default null,
  p_assistant_head_user_id uuid default null
)
returns public.organizations
language plpgsql
security definer
set search_path = public
as $$
declare
  caller uuid := auth.uid();
  caller_name text;
  previous_head uuid;
  previous_assistant uuid;
  selected_profile public.profiles;
  updated_org public.organizations;
begin
  if caller is null or not public.is_super_admin(caller) then
    raise exception 'Super Admin access is required'
      using errcode = '42501';
  end if;

  if p_head_user_id is not null
     and p_head_user_id = p_assistant_head_user_id then
    raise exception 'Head and Assistant Head must be different people'
      using errcode = '22023';
  end if;

  select head_user_id, assistant_head_user_id
    into previous_head, previous_assistant
  from public.organizations
  where id = p_org_id and is_active
  for update;
  if not found then
    raise exception 'Organization not found or inactive'
      using errcode = '22023';
  end if;

  if p_head_user_id is not null then
    select * into selected_profile
    from public.profiles where id = p_head_user_id for update;
    if not found or not coalesce(selected_profile.is_active, false) then
      raise exception 'Head must be an active user'
        using errcode = '22023';
    end if;
    if selected_profile.role = 'super_admin' then
      raise exception 'A Super Admin account cannot be reassigned as Head'
        using errcode = '22023';
    end if;
    if exists (
      select 1 from public.organizations
      where id <> p_org_id
        and (head_user_id = p_head_user_id
          or assistant_head_user_id = p_head_user_id)
    ) then
      raise exception 'The selected Head already holds a leadership position in another organization'
        using errcode = '22023';
    end if;
  end if;

  if p_assistant_head_user_id is not null then
    select * into selected_profile
    from public.profiles where id = p_assistant_head_user_id for update;
    if not found or not coalesce(selected_profile.is_active, false) then
      raise exception 'Assistant Head must be an active user'
        using errcode = '22023';
    end if;
    if selected_profile.role = 'super_admin' then
      raise exception 'A Super Admin account cannot be reassigned as Assistant Head'
        using errcode = '22023';
    end if;
    if exists (
      select 1 from public.organizations
      where id <> p_org_id
        and (head_user_id = p_assistant_head_user_id
          or assistant_head_user_id = p_assistant_head_user_id)
    ) then
      raise exception 'The selected Assistant Head already holds a leadership position in another organization'
        using errcode = '22023';
    end if;
  end if;

  update public.organizations
  set
    head_user_id = p_head_user_id,
    assistant_head_user_id = p_assistant_head_user_id,
    updated_at = now()
  where id = p_org_id
  returning * into updated_org;

  if p_head_user_id is not null then
    update public.profiles
    set role = 'dept_head', org_id = p_org_id, updated_at = now()
    where id = p_head_user_id;
  end if;

  if p_assistant_head_user_id is not null then
    update public.profiles
    set role = 'assistant_head', org_id = p_org_id, updated_at = now()
    where id = p_assistant_head_user_id;
  end if;

  if previous_head is not null
     and previous_head is distinct from p_head_user_id
     and previous_head is distinct from p_assistant_head_user_id
     and not exists (
       select 1 from public.organizations
       where head_user_id = previous_head or assistant_head_user_id = previous_head
     ) then
    update public.profiles
    set role = 'employee', updated_at = now()
    where id = previous_head
      and role in ('dept_head', 'department_head', 'assistant_head');
  end if;

  if previous_assistant is not null
     and previous_assistant is distinct from p_head_user_id
     and previous_assistant is distinct from p_assistant_head_user_id
     and not exists (
       select 1 from public.organizations
       where head_user_id = previous_assistant
          or assistant_head_user_id = previous_assistant
     ) then
    update public.profiles
    set role = 'employee', updated_at = now()
    where id = previous_assistant
      and role in ('dept_head', 'department_head', 'assistant_head');
  end if;

  -- Re-run the task routing trigger for active work in this organization.
  update public.tasks
  set reviewer_id = reviewer_id
  where org_id = p_org_id
    and deleted_at is null
    and status not in ('completed', 'cancelled')
    and p_head_user_id is not null
    and p_assistant_head_user_id is not null;

  select full_name into caller_name from public.profiles where id = caller;
  insert into public.audit_events (
    actor_id, actor_name, entity_type, entity_id, action,
    before_data, after_data, org_id
  ) values (
    caller,
    coalesce(caller_name, 'Super Admin'),
    'organization',
    p_org_id::text,
    'organization.leadership_changed',
    jsonb_build_object(
      'headUserId', previous_head,
      'assistantHeadUserId', previous_assistant
    ),
    jsonb_build_object(
      'headUserId', p_head_user_id,
      'assistantHeadUserId', p_assistant_head_user_id
    ),
    p_org_id
  );

  return updated_org;
end;
$$;

revoke all on function public.set_organization_leadership(uuid, uuid, uuid)
  from public, anon;
grant execute on function public.set_organization_leadership(uuid, uuid, uuid)
  to authenticated;

-- This trigger makes the reciprocal reviewer authoritative regardless of which
-- task screen or service performs the assignment.
create or replace function public.route_organization_leadership_review()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  org_head uuid;
  org_assistant uuid;
  expected_reviewer uuid;
  expected_label text;
  reviewer_active boolean;
begin
  if new.org_id is null or new.assigned_to is null then
    return new;
  end if;

  select head_user_id, assistant_head_user_id
    into org_head, org_assistant
  from public.organizations
  where id = new.org_id;

  if new.assigned_to = org_head then
    expected_reviewer := org_assistant;
    expected_label := 'Assistant Head';
  elsif new.assigned_to = org_assistant then
    expected_reviewer := org_head;
    expected_label := 'Head';
  else
    return new;
  end if;

  new.backup_reviewer_id := null;

  if expected_reviewer is not null then
    select is_active into reviewer_active
    from public.profiles where id = expected_reviewer;
  end if;

  if expected_reviewer is null or not coalesce(reviewer_active, false) then
    new.reviewer_id := null;
    if new.status = 'for_review' then
      raise exception 'Assign an active % for this organization before submitting leadership work', expected_label
        using errcode = '22023';
    end if;
    return new;
  end if;

  new.reviewer_id := expected_reviewer;
  return new;
end;
$$;

-- Backfill routable tasks before enabling the strict submission-time check.
update public.tasks t
set
  reviewer_id = case
    when t.assigned_to = o.head_user_id then o.assistant_head_user_id
    when t.assigned_to = o.assistant_head_user_id then o.head_user_id
    else t.reviewer_id
  end,
  backup_reviewer_id = null
from public.organizations o, public.profiles reviewer
where reviewer.id = case
    when t.assigned_to = o.head_user_id then o.assistant_head_user_id
    when t.assigned_to = o.assistant_head_user_id then o.head_user_id
  end
  and t.org_id = o.id
  and reviewer.is_active
  and t.deleted_at is null
  and t.status not in ('completed', 'cancelled')
  and (
    t.assigned_to = o.head_user_id
    or t.assigned_to = o.assistant_head_user_id
  );

drop trigger if exists tasks_route_organization_leadership_review
  on public.tasks;
create trigger tasks_route_organization_leadership_review
before insert or update of
  assigned_to, recommendation_lead_id, org_id,
  reviewer_id, backup_reviewer_id, status
on public.tasks
for each row execute function public.route_organization_leadership_review();
