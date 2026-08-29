-- Heads and Assistant Heads must already belong to the organization they are
-- being asked to lead. This prevents the leadership RPC (or a direct database
-- update) from silently relocating a person from another department, section,
-- division, unit, Board, or committee.
--
-- Board/committee approvers use organization_memberships and the separate
-- set_organization_approvers RPC, so that intentional secondary workflow is
-- unchanged by this guard.

create or replace function public.guard_organization_leadership_membership()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  selected_name text;
begin
  if new.head_user_id is not null then
    select full_name into selected_name
    from public.profiles
    where id = new.head_user_id
      and is_active
      and org_id = new.id;

    if selected_name is null then
      raise exception 'Head must already be an active member of this organization before being assigned'
        using errcode = '22023';
    end if;
  end if;

  if new.assistant_head_user_id is not null then
    select full_name into selected_name
    from public.profiles
    where id = new.assistant_head_user_id
      and is_active
      and org_id = new.id;

    if selected_name is null then
      raise exception 'Assistant Head must already be an active member of this organization before being assigned'
        using errcode = '22023';
    end if;
  end if;

  return new;
end;
$$;

drop trigger if exists organizations_guard_leadership_membership on public.organizations;
create trigger organizations_guard_leadership_membership
before update of head_user_id, assistant_head_user_id on public.organizations
for each row execute function public.guard_organization_leadership_membership();

revoke all on function public.guard_organization_leadership_membership() from public, anon, authenticated;
