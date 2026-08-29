-- Creates a project, its members, and its initial milestones in one secured
-- transaction. The browser calls this RPC instead of performing multiple
-- RLS-sensitive inserts that can leave a partially-created project.

create or replace function public.create_project_with_details(p_payload jsonb)
returns public.projects
language plpgsql
security definer
set search_path = public
as $$
declare
  caller uuid := auth.uid();
  caller_profile public.profiles;
  target_org uuid;
  selected_owner uuid;
  project_status text := coalesce(nullif(trim(p_payload ->> 'status'), ''), 'planning');
  project_priority text := coalesce(nullif(trim(p_payload ->> 'priority'), ''), 'medium');
  created_project public.projects;
  member_value text;
  milestone_value jsonb;
begin
  if caller is null then
    raise exception 'Authentication is required to create a project'
      using errcode = '42501';
  end if;

  select * into caller_profile
  from public.profiles
  where id = caller and is_active;
  if not found then
    raise exception 'An active eFlow profile is required to create a project'
      using errcode = '42501';
  end if;

  if nullif(trim(p_payload ->> 'title'), '') is null then
    raise exception 'Project title is required'
      using errcode = '22023';
  end if;

  if project_status not in ('planning', 'active', 'on_hold', 'completed', 'archived') then
    raise exception 'Invalid project status'
      using errcode = '22023';
  end if;
  if project_priority not in ('low', 'medium', 'high') then
    raise exception 'Invalid project priority'
      using errcode = '22023';
  end if;

  target_org := coalesce(
    nullif(p_payload ->> 'org_id', '')::uuid,
    caller_profile.org_id
  );

  if not public.can_create_scoped_work(target_org, caller) then
    raise exception 'You cannot create projects in this organization'
      using errcode = '42501';
  end if;

  selected_owner := coalesce(
    nullif(p_payload ->> 'owner_id', '')::uuid,
    caller
  );
  if not exists (
    select 1 from public.profiles
    where id = selected_owner and is_active
  ) then
    raise exception 'Project owner must be an active eFlow user'
      using errcode = '22023';
  end if;

  insert into public.projects (
    title,
    description,
    org_id,
    owner_id,
    status,
    priority,
    start_date,
    target_date,
    created_by
  ) values (
    trim(p_payload ->> 'title'),
    coalesce(p_payload ->> 'description', ''),
    target_org,
    selected_owner,
    project_status,
    project_priority,
    nullif(p_payload ->> 'start_date', '')::date,
    nullif(p_payload ->> 'target_date', '')::date,
    caller
  )
  returning * into created_project;

  insert into public.project_members (project_id, user_id, role)
  values (created_project.id, selected_owner, 'owner')
  on conflict (project_id, user_id) do update set role = excluded.role;

  for member_value in
    select value
    from jsonb_array_elements_text(coalesce(p_payload -> 'member_ids', '[]'::jsonb))
  loop
    if member_value <> '' and member_value::uuid <> selected_owner then
      if not exists (
        select 1 from public.profiles
        where id = member_value::uuid and is_active
      ) then
        raise exception 'Every project member must be an active eFlow user'
          using errcode = '22023';
      end if;

      insert into public.project_members (project_id, user_id, role)
      values (created_project.id, member_value::uuid, 'member')
      on conflict (project_id, user_id) do nothing;
    end if;
  end loop;

  for milestone_value in
    select value
    from jsonb_array_elements(coalesce(p_payload -> 'milestones', '[]'::jsonb))
  loop
    if nullif(trim(milestone_value ->> 'title'), '') is not null then
      insert into public.milestones (
        project_id,
        title,
        description,
        due_date,
        sort_order
      ) values (
        created_project.id,
        trim(milestone_value ->> 'title'),
        coalesce(milestone_value ->> 'description', ''),
        nullif(milestone_value ->> 'due_date', '')::date,
        coalesce((milestone_value ->> 'sort_order')::int, 0)
      );
    end if;
  end loop;

  return created_project;
end;
$$;

revoke all on function public.create_project_with_details(jsonb) from public;
grant execute on function public.create_project_with_details(jsonb) to authenticated;

