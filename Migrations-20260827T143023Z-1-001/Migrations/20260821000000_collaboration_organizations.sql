-- Organization foundation for inter-department collaboration.
-- Board and committee membership is additive: a user's home org_id never moves.

alter table public.organizations
  drop constraint if exists organizations_org_type_check;

alter table public.organizations
  add constraint organizations_org_type_check
  check (org_type in ('lgu', 'department', 'division', 'section', 'unit', 'board', 'committee'));

create table if not exists public.organization_memberships (
  organization_id uuid not null references public.organizations(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  membership_role text not null default 'member'
    check (membership_role in ('member', 'primary_approver', 'backup_approver')),
  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (organization_id, user_id)
);

create unique index if not exists organization_memberships_primary_approver_unique
  on public.organization_memberships(organization_id)
  where membership_role = 'primary_approver';
create unique index if not exists organization_memberships_backup_approver_unique
  on public.organization_memberships(organization_id)
  where membership_role = 'backup_approver';
create index if not exists organization_memberships_user_idx
  on public.organization_memberships(user_id, organization_id);

drop trigger if exists organization_memberships_touch on public.organization_memberships;
create trigger organization_memberships_touch
before update on public.organization_memberships
for each row execute function public.touch_updated_at();

create or replace function public.is_organization_member(
  target_organization uuid,
  caller_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select caller_id is not null and exists (
    select 1
    from public.organization_memberships membership
    join public.profiles profile on profile.id = membership.user_id and profile.is_active
    where membership.organization_id = target_organization
      and membership.user_id = caller_id
  );
$$;

create or replace function public.is_organization_approver(
  target_organization uuid,
  caller_id uuid
)
returns boolean
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  organization_row public.organizations;
  profile_row public.profiles;
begin
  if target_organization is null or caller_id is null then return false; end if;
  select * into profile_row from public.profiles where id = caller_id and is_active;
  if not found then return false; end if;
  if profile_row.role = 'super_admin' then return false; end if;

  select * into organization_row
  from public.organizations
  where id = target_organization and is_active;
  if not found then return false; end if;

  if caller_id in (organization_row.head_user_id, organization_row.assistant_head_user_id) then
    return true;
  end if;

  return exists (
    select 1 from public.organization_memberships membership
    where membership.organization_id = target_organization
      and membership.user_id = caller_id
      and membership.membership_role in ('primary_approver', 'backup_approver')
  );
end;
$$;

create or replace function public.set_organization_membership(
  p_organization_id uuid,
  p_user_id uuid,
  p_membership_role text,
  p_reason text default null
)
returns public.organization_memberships
language plpgsql
security definer
set search_path = public
as $$
declare
  caller uuid := auth.uid();
  caller_name text := '';
  result_row public.organization_memberships;
begin
  if caller is null then raise exception 'Not authenticated' using errcode = '42501'; end if;
  if p_membership_role not in ('member', 'primary_approver', 'backup_approver') then
    raise exception 'Invalid organization membership role' using errcode = '22023';
  end if;
  if not exists (select 1 from public.organizations where id = p_organization_id and is_active) then
    raise exception 'Organization not found or inactive' using errcode = 'P0002';
  end if;
  if not exists (select 1 from public.profiles where id = p_user_id and is_active) then
    raise exception 'Member must be an active eFlow user' using errcode = '22023';
  end if;
  if not (
    public.auth_role(caller) = 'super_admin'
    or public.is_organization_approver(p_organization_id, caller)
  ) then
    raise exception 'Only an organization approver or Super Admin may manage memberships'
      using errcode = '42501';
  end if;

  insert into public.organization_memberships (
    organization_id, user_id, membership_role, created_by
  ) values (
    p_organization_id, p_user_id, p_membership_role, caller
  )
  on conflict (organization_id, user_id) do update
    set membership_role = excluded.membership_role,
        updated_at = now()
  returning * into result_row;

  select coalesce(full_name, 'User') into caller_name from public.profiles where id = caller;
  insert into public.audit_events (
    actor_id, actor_name, entity_type, entity_id, action, reason, after_data, org_id
  ) values (
    caller, caller_name, 'organization_membership',
    p_organization_id::text || ':' || p_user_id::text,
    'organization.membership.updated', nullif(btrim(p_reason), ''),
    jsonb_build_object('organizationId', p_organization_id, 'userId', p_user_id, 'role', p_membership_role),
    p_organization_id
  );

  return result_row;
end;
$$;

create or replace function public.set_organization_approvers(
  p_organization_id uuid,
  p_primary_approver_id uuid,
  p_backup_approver_id uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  caller uuid := auth.uid();
begin
  if p_primary_approver_id is not null and p_primary_approver_id = p_backup_approver_id then
    raise exception 'Board Head and Board Assistant Head must be different people' using errcode = '22023';
  end if;
  if public.auth_role(caller) <> 'super_admin'
     and not public.is_organization_approver(p_organization_id, caller) then
    raise exception 'Only an organization approver or Super Admin may configure approvers' using errcode = '42501';
  end if;
  if exists (
    select 1 from unnest(array[p_primary_approver_id, p_backup_approver_id]) candidate
    left join public.profiles profile on profile.id = candidate and profile.is_active
    where candidate is not null and profile.id is null
  ) then raise exception 'Board approvers must be active eFlow users' using errcode = '22023'; end if;
  delete from public.organization_memberships
  where organization_id = p_organization_id and membership_role in ('primary_approver', 'backup_approver');
  if p_primary_approver_id is not null then
    insert into public.organization_memberships (organization_id, user_id, membership_role, created_by)
    values (p_organization_id, p_primary_approver_id, 'primary_approver', caller)
    on conflict (organization_id, user_id) do update set membership_role = excluded.membership_role, updated_at = now();
  end if;
  if p_backup_approver_id is not null then
    insert into public.organization_memberships (organization_id, user_id, membership_role, created_by)
    values (p_organization_id, p_backup_approver_id, 'backup_approver', caller)
    on conflict (organization_id, user_id) do update set membership_role = excluded.membership_role, updated_at = now();
  end if;
  insert into public.audit_events (actor_id, actor_name, entity_type, entity_id, action, after_data, org_id)
  values (caller, coalesce((select full_name from public.profiles where id = caller), 'User'),
    'organization_membership', p_organization_id::text, 'organization.approvers.updated',
    jsonb_build_object('primaryApproverId', p_primary_approver_id, 'backupApproverId', p_backup_approver_id), p_organization_id);
end;
$$;

alter table public.organization_memberships enable row level security;
drop policy if exists organization_memberships_read on public.organization_memberships;
create policy organization_memberships_read on public.organization_memberships
for select to authenticated using (
  user_id = auth.uid()
  or public.is_organization_member(organization_id, auth.uid())
  or public.is_organization_approver(organization_id, auth.uid())
  or public.auth_role(auth.uid()) = 'super_admin'
);

revoke all on function public.is_organization_member(uuid, uuid) from public, anon;
revoke all on function public.is_organization_approver(uuid, uuid) from public, anon;
revoke all on function public.set_organization_membership(uuid, uuid, text, text) from public, anon;
revoke all on function public.set_organization_approvers(uuid, uuid, uuid) from public, anon;
grant execute on function public.is_organization_member(uuid, uuid) to authenticated;
grant execute on function public.is_organization_approver(uuid, uuid) to authenticated;
grant execute on function public.set_organization_membership(uuid, uuid, text, text) to authenticated;
grant execute on function public.set_organization_approvers(uuid, uuid, uuid) to authenticated;
grant select on public.organization_memberships to authenticated;

notify pgrst, 'reload schema';
