-- Adds an explicit, audited permanent-delete operation for operational
-- projects. Tasks and their history survive through the existing SET NULL
-- foreign keys; project milestones and membership rows cascade with project.

insert into public.role_permissions (role, permission, allowed) values
  ('super_admin', 'projects.delete', true),
  ('dept_head', 'projects.delete', true),
  ('assistant_head', 'projects.delete', true)
on conflict (role, permission) do update
set allowed = excluded.allowed, updated_at = now();

create or replace function public.delete_project_permanently(
  p_project_id uuid,
  p_expected_title text,
  p_reason text
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  caller uuid := auth.uid();
  caller_role text;
  caller_name text;
  project_row public.projects;
  retained_task_count int;
begin
  if caller is null then
    raise exception 'Not authenticated' using errcode = '42501';
  end if;

  select role::text, full_name
    into caller_role, caller_name
  from public.profiles
  where id = caller and is_active;

  if caller_role not in ('super_admin', 'dept_head', 'department_head', 'assistant_head') then
    raise exception 'Only a Head, Assistant Head, or Super Admin may permanently delete a project'
      using errcode = '42501';
  end if;

  select * into project_row
  from public.projects
  where id = p_project_id
  for update;

  if not found then
    raise exception 'Project not found' using errcode = 'P0002';
  end if;

  if caller_role <> 'super_admin'
     and not public.org_in_my_subtree(project_row.org_id, caller) then
    raise exception 'This project is outside your organization scope'
      using errcode = '42501';
  end if;

  if coalesce(p_expected_title, '') <> project_row.title then
    raise exception 'Type the exact project title to confirm deletion'
      using errcode = '22023';
  end if;

  if length(btrim(coalesce(p_reason, ''))) < 5 then
    raise exception 'A deletion reason of at least 5 characters is required'
      using errcode = '22023';
  end if;

  select count(*)::int into retained_task_count
  from public.tasks
  where linked_project_id = p_project_id and deleted_at is null;

  -- Clear both planning links in the same row update. Relying on the two
  -- independent FK actions during project deletion creates a transient state
  -- where linked_project_id is null but milestone_id is still populated; the
  -- task planning guard correctly rejects that inconsistent intermediate row.
  update public.tasks
  set linked_project_id = null,
      milestone_id = null
  where linked_project_id = p_project_id;

  insert into public.audit_events (
    actor_id, actor_name, entity_type, entity_id, action, reason,
    before_data, after_data, org_id
  ) values (
    caller, coalesce(caller_name, 'Administrator'), 'project', p_project_id::text,
    'project.deleted', btrim(p_reason),
    jsonb_build_object(
      'title', project_row.title,
      'status', project_row.status,
      'ownerId', project_row.owner_id,
      'retainedTaskCount', retained_task_count
    ),
    jsonb_build_object('deleted', true, 'taskLinksCleared', retained_task_count),
    project_row.org_id
  );

  delete from public.projects where id = p_project_id;
  return p_project_id;
end;
$$;

revoke all on function public.delete_project_permanently(uuid, text, text)
  from public, anon;
grant execute on function public.delete_project_permanently(uuid, text, text)
  to authenticated;

notify pgrst, 'reload schema';
