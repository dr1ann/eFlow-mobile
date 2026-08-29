-- Super Admin is an organization-wide oversight role for proposals/projects.
-- Project mutations remain owned by the exact-organization Head or Assistant.

create or replace function public.guard_super_admin_project_mutation()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if auth.uid() is not null and public.is_super_admin(auth.uid()) then
    raise exception 'Super Admin project access is read-only. Ask the organization Head or Assistant Head to make this change.'
      using errcode = '42501';
  end if;
  return case when tg_op = 'DELETE' then old else new end;
end;
$$;

drop trigger if exists guard_super_admin_project_mutation on public.projects;
create trigger guard_super_admin_project_mutation
before insert or update or delete on public.projects
for each row execute function public.guard_super_admin_project_mutation();
