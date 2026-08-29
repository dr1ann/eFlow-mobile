-- Let active employees read the budget summary for the organization recorded
-- directly on their profile. Organization memberships and explicit access
-- grants remain supported for collaborative and delegated access.

begin;

create or replace function public.can_view_department_budget(target_org uuid, caller_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select caller_id is not null and (
    exists (
      select 1
      from public.profiles profile
      where profile.id = caller_id
        and profile.is_active
        and profile.org_id = target_org
    )
    or public.is_organization_member(target_org, caller_id)
    or public.can_access_org(caller_id, target_org, 'read')
  );
$$;

revoke all on function public.can_view_department_budget(uuid, uuid) from public, anon;
grant execute on function public.can_view_department_budget(uuid, uuid) to authenticated;

notify pgrst, 'reload schema';

commit;
