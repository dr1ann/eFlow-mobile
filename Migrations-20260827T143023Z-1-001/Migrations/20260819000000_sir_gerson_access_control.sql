-- Sir Gerson updates, Phase 1: page entitlements, per-user access and
-- independently audited organization-scope grants.
--
-- Page/action permissions and data scope deliberately remain separate:
-- granting navigation.projects does not make another department's rows
-- visible. Cross-organization access requires a user_org_scope_grants row.

alter table public.user_permission_overrides
  add column if not exists updated_at timestamptz not null default now();

drop trigger if exists user_permission_overrides_touch on public.user_permission_overrides;
create trigger user_permission_overrides_touch
before update on public.user_permission_overrides
for each row execute function public.touch_updated_at();

create table if not exists public.user_org_scope_grants (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  org_id uuid not null references public.organizations(id) on delete cascade,
  access_level text not null check (access_level in ('read', 'review', 'manage')),
  reason text not null check (length(btrim(reason)) >= 4),
  granted_by uuid not null references public.profiles(id) on delete restrict,
  expires_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id, org_id)
);

create index if not exists user_org_scope_grants_user_idx
  on public.user_org_scope_grants(user_id, expires_at);
create index if not exists user_org_scope_grants_org_idx
  on public.user_org_scope_grants(org_id, access_level);

drop trigger if exists user_org_scope_grants_touch on public.user_org_scope_grants;
create trigger user_org_scope_grants_touch
before update on public.user_org_scope_grants
for each row execute function public.touch_updated_at();

alter table public.user_org_scope_grants enable row level security;

drop policy if exists user_org_scope_grants_read on public.user_org_scope_grants;
create policy user_org_scope_grants_read on public.user_org_scope_grants
for select to authenticated
using (user_id = auth.uid() or public.is_super_admin(auth.uid()));

drop policy if exists user_org_scope_grants_manage on public.user_org_scope_grants;
create policy user_org_scope_grants_manage on public.user_org_scope_grants
for all to authenticated
using (public.is_super_admin(auth.uid()))
with check (
  public.is_super_admin(auth.uid())
  and granted_by = auth.uid()
  and user_id <> auth.uid()
);

-- Seed all newly introduced capabilities without overwriting administrator-
-- tuned values. Super Admin remains an immutable all-access role in both the
-- application and has_permission().
insert into public.role_permissions (role, permission, allowed) values
  ('super_admin', 'navigation.projects', true),
  ('super_admin', 'navigation.tasks', true),
  ('super_admin', 'navigation.reviews', true),
  ('super_admin', 'navigation.team_supervision', true),
  ('super_admin', 'navigation.team_intelligence', true),
  ('super_admin', 'navigation.reports', true),
  ('super_admin', 'navigation.announcements', true),
  ('super_admin', 'navigation.user_management', true),
  ('super_admin', 'navigation.organization', true),
  ('super_admin', 'navigation.audit', true),
  ('super_admin', 'navigation.system_settings', true),
  ('super_admin', 'navigation.data_tools', true),
  ('super_admin', 'database.backup', true),

  ('dept_head', 'navigation.projects', true),
  ('dept_head', 'navigation.tasks', true),
  ('dept_head', 'navigation.reviews', true),
  ('dept_head', 'navigation.team_supervision', true),
  ('dept_head', 'navigation.team_intelligence', true),
  ('dept_head', 'navigation.reports', true),
  ('dept_head', 'navigation.announcements', true),
  ('dept_head', 'navigation.user_management', false),
  ('dept_head', 'navigation.organization', false),
  ('dept_head', 'navigation.audit', false),
  ('dept_head', 'navigation.system_settings', false),
  ('dept_head', 'navigation.data_tools', false),
  ('dept_head', 'database.backup', false),

  ('assistant_head', 'navigation.projects', true),
  ('assistant_head', 'navigation.tasks', true),
  ('assistant_head', 'navigation.reviews', true),
  ('assistant_head', 'navigation.team_supervision', true),
  ('assistant_head', 'navigation.team_intelligence', true),
  ('assistant_head', 'navigation.reports', true),
  ('assistant_head', 'navigation.announcements', true),
  ('assistant_head', 'navigation.user_management', false),
  ('assistant_head', 'navigation.organization', false),
  ('assistant_head', 'navigation.audit', false),
  ('assistant_head', 'navigation.system_settings', false),
  ('assistant_head', 'navigation.data_tools', false),
  ('assistant_head', 'database.backup', false),

  ('employee', 'navigation.projects', true),
  ('employee', 'navigation.tasks', true),
  ('employee', 'navigation.reviews', true),
  ('employee', 'navigation.team_supervision', false),
  ('employee', 'navigation.team_intelligence', false),
  ('employee', 'navigation.reports', true),
  ('employee', 'navigation.announcements', true),
  ('employee', 'navigation.user_management', false),
  ('employee', 'navigation.organization', false),
  ('employee', 'navigation.audit', false),
  ('employee', 'navigation.system_settings', false),
  ('employee', 'navigation.data_tools', false),
  ('employee', 'database.backup', false)
on conflict (role, permission) do nothing;

create or replace function public.has_permission(
  p_user_id uuid,
  p_permission text
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select case
    when p_user_id is null or nullif(btrim(p_permission), '') is null then false
    when exists (
      select 1 from public.profiles p
      where p.id = p_user_id and p.is_active and p.role = 'super_admin'
    ) then true
    else coalesce(
      (
        select o.allowed
        from public.user_permission_overrides o
        where o.user_id = p_user_id and o.permission = p_permission
      ),
      (
        select rp.allowed
        from public.profiles p
        join public.role_permissions rp on rp.role = p.role
        where p.id = p_user_id
          and p.is_active
          and rp.permission = p_permission
      ),
      false
    )
  end;
$$;

create or replace function public.can_access_org(
  p_user_id uuid,
  p_org_id uuid,
  p_access_level text default 'read'
)
returns boolean
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  requested_rank integer;
  caller_role text;
begin
  if p_user_id is null or p_org_id is null then return false; end if;
  requested_rank := case p_access_level
    when 'read' then 1
    when 'review' then 2
    when 'manage' then 3
    else 99
  end;
  if requested_rank = 99 then return false; end if;

  caller_role := public.auth_role(p_user_id);
  if caller_role = 'super_admin' then return true; end if;

  -- Preserve the existing Head/Assistant Head organization subtree scope.
  if caller_role in ('dept_head', 'department_head', 'assistant_head')
     and public.org_in_my_subtree(p_org_id, p_user_id) then
    return true;
  end if;

  -- An explicit grant covers the selected organization and its descendants.
  return exists (
    select 1
    from public.user_org_scope_grants grant_row
    join public.organizations grant_org on grant_org.id = grant_row.org_id
    join public.organizations target_org on target_org.id = p_org_id
    where grant_row.user_id = p_user_id
      and (grant_row.expires_at is null or grant_row.expires_at > now())
      and (
        target_org.path::text = grant_org.path::text
        or target_org.path::text like grant_org.path::text || '.%'
      )
      and case grant_row.access_level
        when 'read' then 1
        when 'review' then 2
        when 'manage' then 3
        else 0
      end >= requested_rank
  );
end;
$$;

-- Fold explicit scope grants into the latest canonical project/task helpers.
-- Existing ownership, membership, assignment and review visibility remains.
create or replace function public.can_see_project(target_project uuid, caller_id uuid)
returns boolean
language plpgsql stable security definer set search_path = public
as $$
declare
  proj_org uuid;
  proj_owner uuid;
begin
  if caller_id is null then return false; end if;
  if public.is_super_admin(caller_id) then return true; end if;
  select org_id, owner_id into proj_org, proj_owner
  from public.projects where id = target_project;
  if not found then return false; end if;

  return proj_owner = caller_id
    or public.is_project_member(target_project, caller_id)
    or exists (
      select 1 from public.tasks task_row
      where task_row.linked_project_id = target_project
        and task_row.deleted_at is null
        and (
          task_row.assigned_to = caller_id
          or task_row.recommendation_lead_id = caller_id
          or coalesce(to_jsonb(task_row.team_member_ids), '[]'::jsonb) ? caller_id::text
        )
    )
    or public.can_access_org(caller_id, proj_org, 'read');
end;
$$;

create or replace function public.can_manage_project(target_project uuid, caller_id uuid)
returns boolean
language plpgsql stable security definer set search_path = public
as $$
declare
  proj_org uuid;
  proj_owner uuid;
  proj_creator uuid;
begin
  if caller_id is null then return false; end if;
  if public.is_super_admin(caller_id) then return true; end if;
  select org_id, owner_id, created_by into proj_org, proj_owner, proj_creator
  from public.projects where id = target_project;
  if not found then return false; end if;

  return proj_owner = caller_id
    or proj_creator = caller_id
    or public.can_access_org(caller_id, proj_org, 'manage');
end;
$$;

create or replace function public.can_see_task(target_task uuid, caller_id uuid)
returns boolean
language plpgsql stable security definer set search_path = public
as $$
declare
  row_task public.tasks;
begin
  if caller_id is null then return false; end if;
  if public.is_super_admin(caller_id) then return true; end if;
  select * into row_task from public.tasks
  where id = target_task and deleted_at is null;
  if not found then return false; end if;

  return row_task.assigned_to = caller_id
    or row_task.created_by = caller_id
    or row_task.recommendation_lead_id = caller_id
    or row_task.reviewer_id = caller_id
    or row_task.backup_reviewer_id = caller_id
    or coalesce(to_jsonb(row_task.team_member_ids), '[]'::jsonb) ? caller_id::text
    or (
      row_task.linked_project_id is not null
      and public.is_project_member(row_task.linked_project_id, caller_id)
    )
    or public.can_access_org(caller_id, row_task.org_id, 'read');
end;
$$;

create or replace function public.can_manage_task(target_task uuid, caller_id uuid)
returns boolean
language plpgsql stable security definer set search_path = public
as $$
declare
  row_task public.tasks;
begin
  if caller_id is null then return false; end if;
  if public.is_super_admin(caller_id) then return true; end if;
  select * into row_task from public.tasks
  where id = target_task and deleted_at is null;
  if not found then return false; end if;

  return row_task.created_by = caller_id
    or row_task.recommendation_lead_id = caller_id
    or public.can_access_org(caller_id, row_task.org_id, 'manage');
end;
$$;

-- Server-side audit coverage means direct PostgREST mutations are recorded too.
create or replace function public.audit_access_control_change()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  caller uuid := auth.uid();
  caller_name text := '';
  entity_key text;
  target_org uuid;
begin
  select coalesce(full_name, '') into caller_name
  from public.profiles where id = caller;

  if tg_table_name = 'role_permissions' then
    entity_key := coalesce(new.role, old.role) || ':' || coalesce(new.permission, old.permission);
  elsif tg_table_name = 'user_permission_overrides' then
    entity_key := coalesce(new.user_id, old.user_id)::text || ':' || coalesce(new.permission, old.permission);
  else
    entity_key := coalesce(new.id, old.id)::text;
    target_org := coalesce(new.org_id, old.org_id);
  end if;

  insert into public.audit_events (
    actor_id, actor_name, entity_type, entity_id, action,
    before_data, after_data, org_id
  ) values (
    caller, caller_name, tg_table_name, entity_key,
    'access.' || tg_table_name || '.' || lower(tg_op),
    case when tg_op in ('UPDATE', 'DELETE') then to_jsonb(old) else null end,
    case when tg_op in ('INSERT', 'UPDATE') then to_jsonb(new) else null end,
    target_org
  );
  if tg_op = 'DELETE' then return old; end if;
  return new;
end;
$$;

drop trigger if exists role_permissions_audit on public.role_permissions;
create trigger role_permissions_audit
after insert or update or delete on public.role_permissions
for each row execute function public.audit_access_control_change();

drop trigger if exists user_permission_overrides_audit on public.user_permission_overrides;
create trigger user_permission_overrides_audit
after insert or update or delete on public.user_permission_overrides
for each row execute function public.audit_access_control_change();

drop trigger if exists user_org_scope_grants_audit on public.user_org_scope_grants;
create trigger user_org_scope_grants_audit
after insert or update or delete on public.user_org_scope_grants
for each row execute function public.audit_access_control_change();

grant execute on function public.has_permission(uuid, text) to authenticated;
grant execute on function public.can_access_org(uuid, uuid, text) to authenticated;

do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    if not exists (
      select 1 from pg_publication_tables
      where pubname = 'supabase_realtime'
        and schemaname = 'public'
        and tablename = 'role_permissions'
    ) then
      alter publication supabase_realtime add table public.role_permissions;
    end if;
    if not exists (
      select 1 from pg_publication_tables
      where pubname = 'supabase_realtime'
        and schemaname = 'public'
        and tablename = 'user_permission_overrides'
    ) then
      alter publication supabase_realtime add table public.user_permission_overrides;
    end if;
    if not exists (
      select 1 from pg_publication_tables
      where pubname = 'supabase_realtime'
        and schemaname = 'public'
        and tablename = 'user_org_scope_grants'
    ) then
      alter publication supabase_realtime add table public.user_org_scope_grants;
    end if;
  end if;
end;
$$;
