-- Super Admin is an organization-wide oversight role for operational work.
-- Task mutations remain owned by the exact-organization Head, Assistant Head,
-- Team Leader, reviewer, and assigned contributors through existing workflows.

create or replace function public.guard_super_admin_task_mutation()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if auth.uid() is not null and public.is_super_admin(auth.uid()) then
    raise exception 'Super Admin task access is read-only. Ask the responsible organization to make this change.'
      using errcode = '42501';
  end if;
  return case when tg_op = 'DELETE' then old else new end;
end;
$$;

drop trigger if exists guard_super_admin_task_mutation on public.tasks;
create trigger guard_super_admin_task_mutation
before insert or update or delete on public.tasks
for each row execute function public.guard_super_admin_task_mutation();
