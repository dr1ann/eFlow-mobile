-- Allows the roles that eFlow exposes the Projects workspace to create
-- operational projects and their initial tasks in their own organization
-- subtree. This is intentionally narrower than a client-side permission:
-- the caller must be authenticated, create the row themselves, and be an
-- administrator, Head, Assistant Head, or legacy Department Head.

create or replace function public.can_create_scoped_work(
  target_org uuid,
  caller_id uuid
)
returns boolean
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  caller_role text;
begin
  if caller_id is null then
    return false;
  end if;

  select role::text
    into caller_role
  from public.profiles
  where id = caller_id
    and is_active;

  if caller_role = 'super_admin' then
    return true;
  end if;

  return caller_role in ('dept_head', 'department_head', 'assistant_head')
    and target_org is not null
    and public.org_in_my_subtree(target_org, caller_id);
end;
$$;

drop policy if exists projects_insert on public.projects;
create policy projects_insert on public.projects
  for insert to authenticated
  with check (
    created_by = auth.uid()
    and public.can_create_scoped_work(org_id, auth.uid())
  );

drop policy if exists tasks_insert on public.tasks;
create policy tasks_insert on public.tasks
  for insert to authenticated
  with check (
    created_by = auth.uid()
    and public.can_create_scoped_work(org_id, auth.uid())
  );
