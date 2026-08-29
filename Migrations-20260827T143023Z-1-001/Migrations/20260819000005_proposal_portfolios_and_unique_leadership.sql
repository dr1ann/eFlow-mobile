-- Makes proposal/program identity first-class on operational projects and
-- makes organization leadership slots authoritative across every write path.

alter table public.projects
  add column if not exists proposal_id text,
  add column if not exists proposal_title text,
  add column if not exists program_id text,
  add column if not exists program_title text,
  add column if not exists source_type text not null default 'standalone',
  add column if not exists source_file_name text;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'projects_source_type_check'
      and conrelid = 'public.projects'::regclass
  ) then
    alter table public.projects
      add constraint projects_source_type_check
      check (source_type in ('ai_pdf', 'manual', 'standalone'));
  end if;
end;
$$;

-- Existing imports already retain this hierarchy on their linked tasks.
with task_hierarchy as (
  select distinct on (linked_project_id)
    linked_project_id,
    proposal_id,
    proposal_title,
    program_id,
    program_title
  from public.tasks
  where linked_project_id is not null
    and (proposal_id is not null or proposal_title is not null)
  order by linked_project_id, created_at desc
)
update public.projects p
set
  proposal_id = coalesce(p.proposal_id, h.proposal_id),
  proposal_title = coalesce(p.proposal_title, h.proposal_title),
  program_id = coalesce(p.program_id, h.program_id),
  program_title = coalesce(p.program_title, h.program_title)
from task_hierarchy h
where h.linked_project_id = p.id;

-- Empty imported projects have no task row to backfill from, but their source
-- proposal is preserved in the existing description compatibility contract.
update public.projects
set
  proposal_title = btrim(substr(description, length('Imported via proposal:') + 1)),
  source_type = 'ai_pdf'
where proposal_title is null
  and lower(description) like 'imported via proposal:%';

update public.projects
set source_type = 'ai_pdf'
where lower(description) like 'imported via proposal:%';

update public.projects
set
  proposal_title = btrim(substr(description, length('Manual plan:') + 1)),
  source_type = 'manual'
where proposal_title is null
  and lower(description) like 'manual plan:%';

update public.projects
set source_type = 'manual'
where lower(description) like 'manual plan:%';

update public.projects
set
  proposal_id = 'proposal-' || md5(lower(proposal_title)),
  source_file_name = case
    when source_type = 'ai_pdf' and source_file_name is null
      then regexp_replace(proposal_title, '\.pdf$', '', 'i') || '.pdf'
    else source_file_name
  end
where proposal_title is not null
  and proposal_id is null;

create index if not exists projects_proposal_scope_idx
  on public.projects(org_id, proposal_id);
create index if not exists projects_program_idx
  on public.projects(program_id);

-- Reconcile legacy direct role edits. Existing organization slots win. When a
-- slot is empty, adopt the earliest active matching profile in that org.
with ranked_heads as (
  select
    p.id,
    p.org_id,
    row_number() over (partition by p.org_id order by p.created_at, p.id) as position
  from public.profiles p
  where p.is_active
    and p.org_id is not null
    and p.role in ('dept_head', 'department_head')
)
update public.organizations o
set head_user_id = ranked_heads.id,
    updated_at = now()
from ranked_heads
where o.id = ranked_heads.org_id
  and o.head_user_id is null
  and ranked_heads.position = 1
  and ranked_heads.id is distinct from o.assistant_head_user_id;

with ranked_assistants as (
  select
    p.id,
    p.org_id,
    row_number() over (partition by p.org_id order by p.created_at, p.id) as position
  from public.profiles p
  where p.is_active
    and p.org_id is not null
    and p.role = 'assistant_head'
)
update public.organizations o
set assistant_head_user_id = ranked_assistants.id,
    updated_at = now()
from ranked_assistants
where o.id = ranked_assistants.org_id
  and o.assistant_head_user_id is null
  and ranked_assistants.position = 1
  and ranked_assistants.id is distinct from o.head_user_id;

update public.profiles p
set role = 'dept_head',
    org_id = o.id,
    updated_at = now()
from public.organizations o
where o.head_user_id = p.id
  and (p.role <> 'dept_head' or p.org_id is distinct from o.id);

update public.profiles p
set role = 'assistant_head',
    org_id = o.id,
    updated_at = now()
from public.organizations o
where o.assistant_head_user_id = p.id
  and (p.role <> 'assistant_head' or p.org_id is distinct from o.id);

update public.profiles p
set role = 'employee', updated_at = now()
where p.is_active
  and p.role in ('dept_head', 'department_head')
  and not exists (
    select 1 from public.organizations o where o.head_user_id = p.id
  );

update public.profiles p
set role = 'employee', updated_at = now()
where p.is_active
  and p.role = 'assistant_head'
  and not exists (
    select 1 from public.organizations o where o.assistant_head_user_id = p.id
  );

create unique index if not exists profiles_one_active_head_per_org
  on public.profiles(org_id)
  where is_active and role in ('dept_head', 'department_head');
create unique index if not exists profiles_one_active_assistant_per_org
  on public.profiles(org_id)
  where is_active and role = 'assistant_head';
create unique index if not exists organizations_unique_head_user
  on public.organizations(head_user_id)
  where head_user_id is not null;
create unique index if not exists organizations_unique_assistant_user
  on public.organizations(assistant_head_user_id)
  where assistant_head_user_id is not null;

create or replace function public.guard_profile_leadership_integrity()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if new.is_active and new.role in ('dept_head', 'department_head') then
    if new.org_id is null or not exists (
      select 1 from public.organizations o
      where o.id = new.org_id and o.head_user_id = new.id and o.is_active
    ) then
      raise exception 'Assign Head through the organization leadership slot'
        using errcode = '23514';
    end if;
  elsif new.is_active and new.role = 'assistant_head' then
    if new.org_id is null or not exists (
      select 1 from public.organizations o
      where o.id = new.org_id and o.assistant_head_user_id = new.id and o.is_active
    ) then
      raise exception 'Assign Assistant Head through the organization leadership slot'
        using errcode = '23514';
    end if;
  end if;

  if tg_op = 'UPDATE' and exists (
    select 1 from public.organizations o
    where o.head_user_id = old.id
      and (not new.is_active or new.role not in ('dept_head', 'department_head') or new.org_id is distinct from o.id)
  ) then
    raise exception 'Clear or replace this user in the organization Head slot first'
      using errcode = '23514';
  end if;

  if tg_op = 'UPDATE' and exists (
    select 1 from public.organizations o
    where o.assistant_head_user_id = old.id
      and (not new.is_active or new.role <> 'assistant_head' or new.org_id is distinct from o.id)
  ) then
    raise exception 'Clear or replace this user in the organization Assistant Head slot first'
      using errcode = '23514';
  end if;
  return new;
end;
$$;

drop trigger if exists guard_profile_leadership_integrity on public.profiles;
create trigger guard_profile_leadership_integrity
before insert or update of role, org_id, is_active on public.profiles
for each row execute function public.guard_profile_leadership_integrity();

-- Heads and Assistant Heads operate only inside their exact organization.
create or replace function public.can_create_scoped_work(target_org uuid, caller_id uuid)
returns boolean
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  caller_profile public.profiles;
begin
  if caller_id is null then return false; end if;
  select * into caller_profile
  from public.profiles
  where id = caller_id and is_active;
  if not found then return false; end if;
  if caller_profile.role = 'super_admin' then return true; end if;
  return caller_profile.role in ('dept_head', 'department_head', 'assistant_head')
    and target_org is not null
    and target_org = caller_profile.org_id;
end;
$$;

create or replace function public.can_see_project(target_project uuid, caller_id uuid)
returns boolean
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  caller_profile public.profiles;
  project_org uuid;
  project_owner uuid;
begin
  select * into caller_profile from public.profiles where id = caller_id and is_active;
  if not found then return false; end if;
  if caller_profile.role = 'super_admin' then return true; end if;
  select org_id, owner_id into project_org, project_owner from public.projects where id = target_project;
  if not found then return false; end if;
  if caller_profile.role in ('dept_head', 'department_head', 'assistant_head') then
    return project_org = caller_profile.org_id;
  end if;
  return project_owner = caller_id or public.is_project_member(target_project, caller_id);
end;
$$;

drop policy if exists "projects readable in scope" on public.projects;
drop policy if exists projects_read on public.projects;
drop policy if exists projects_exact_scope_read on public.projects;
create policy projects_exact_scope_read on public.projects
for select to authenticated
using (public.can_see_project(id, auth.uid()));

-- Keep the public RPC and its return type stable while accepting the additive
-- proposal metadata included by the updated project service.
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
  project_source text := coalesce(nullif(trim(p_payload ->> 'source_type'), ''), 'standalone');
  created_project public.projects;
  member_value text;
  milestone_value jsonb;
begin
  if caller is null then raise exception 'Authentication is required to create a project' using errcode = '42501'; end if;
  select * into caller_profile from public.profiles where id = caller and is_active;
  if not found then raise exception 'An active eFlow profile is required to create a project' using errcode = '42501'; end if;
  if nullif(trim(p_payload ->> 'title'), '') is null then raise exception 'Project title is required' using errcode = '22023'; end if;
  if project_status not in ('planning', 'active', 'on_hold', 'completed', 'archived') then raise exception 'Invalid project status' using errcode = '22023'; end if;
  if project_priority not in ('low', 'medium', 'high') then raise exception 'Invalid project priority' using errcode = '22023'; end if;
  if project_source not in ('ai_pdf', 'manual', 'standalone') then raise exception 'Invalid project source type' using errcode = '22023'; end if;

  target_org := coalesce(nullif(p_payload ->> 'org_id', '')::uuid, caller_profile.org_id);
  if not public.can_create_scoped_work(target_org, caller) then raise exception 'You cannot create projects in this organization' using errcode = '42501'; end if;
  selected_owner := coalesce(nullif(p_payload ->> 'owner_id', '')::uuid, caller);
  if not exists (select 1 from public.profiles where id = selected_owner and is_active) then raise exception 'Project owner must be an active eFlow user' using errcode = '22023'; end if;

  insert into public.projects (
    title, description, org_id, owner_id, status, priority, start_date, target_date,
    created_by, proposal_id, proposal_title, program_id, program_title, source_type, source_file_name
  ) values (
    trim(p_payload ->> 'title'), coalesce(p_payload ->> 'description', ''), target_org,
    selected_owner, project_status, project_priority, nullif(p_payload ->> 'start_date', '')::date,
    nullif(p_payload ->> 'target_date', '')::date, caller, nullif(p_payload ->> 'proposal_id', ''),
    nullif(p_payload ->> 'proposal_title', ''), nullif(p_payload ->> 'program_id', ''),
    nullif(p_payload ->> 'program_title', ''), project_source, nullif(p_payload ->> 'source_file_name', '')
  ) returning * into created_project;

  insert into public.project_members (project_id, user_id, role)
  values (created_project.id, selected_owner, 'owner')
  on conflict (project_id, user_id) do update set role = excluded.role;

  for member_value in select value from jsonb_array_elements_text(coalesce(p_payload -> 'member_ids', '[]'::jsonb)) loop
    if member_value <> '' and member_value::uuid <> selected_owner then
      if not exists (select 1 from public.profiles where id = member_value::uuid and is_active) then raise exception 'Every project member must be an active eFlow user' using errcode = '22023'; end if;
      insert into public.project_members (project_id, user_id, role)
      values (created_project.id, member_value::uuid, 'member')
      on conflict (project_id, user_id) do nothing;
    end if;
  end loop;

  for milestone_value in select value from jsonb_array_elements(coalesce(p_payload -> 'milestones', '[]'::jsonb)) loop
    if nullif(trim(milestone_value ->> 'title'), '') is not null then
      insert into public.milestones (project_id, title, description, due_date, sort_order)
      values (created_project.id, trim(milestone_value ->> 'title'), coalesce(milestone_value ->> 'description', ''), nullif(milestone_value ->> 'due_date', '')::date, coalesce((milestone_value ->> 'sort_order')::int, 0));
    end if;
  end loop;
  return created_project;
end;
$$;

revoke all on function public.create_project_with_details(jsonb) from public;
grant execute on function public.create_project_with_details(jsonb) to authenticated;
