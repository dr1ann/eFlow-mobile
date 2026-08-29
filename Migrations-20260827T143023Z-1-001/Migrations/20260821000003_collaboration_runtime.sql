-- Operational collaboration relationships and separated visibility/mutation authority.

alter table public.projects
  add column if not exists source_collaboration_draft_id uuid references public.proposal_collaboration_drafts(id) on delete set null,
  add column if not exists source_collaboration_revision_id uuid references public.proposal_collaboration_revisions(id) on delete set null;

alter table public.tasks
  add column if not exists review_route_mode text not null default 'organization_default',
  add column if not exists source_collaboration_draft_id uuid references public.proposal_collaboration_drafts(id) on delete set null,
  add column if not exists source_collaboration_revision_id uuid references public.proposal_collaboration_revisions(id) on delete set null;

alter table public.tasks drop constraint if exists tasks_review_route_mode_check;
alter table public.tasks add constraint tasks_review_route_mode_check
  check (review_route_mode in ('organization_default', 'explicit', 'governance'));

create table if not exists public.project_organizations (
  project_id uuid not null references public.projects(id) on delete cascade,
  organization_id uuid not null references public.organizations(id) on delete restrict,
  participation_role text not null check (participation_role in ('owner', 'participant', 'governance')),
  staffing_enabled boolean not null default true,
  source_draft_id uuid references public.proposal_collaboration_drafts(id) on delete set null,
  source_revision_id uuid references public.proposal_collaboration_revisions(id) on delete set null,
  created_at timestamptz not null default now(),
  primary key (project_id, organization_id)
);

create unique index if not exists project_organizations_one_owner
  on public.project_organizations(project_id)
  where participation_role = 'owner';
create index if not exists project_organizations_org_idx
  on public.project_organizations(organization_id, project_id);

create table if not exists public.milestone_organizations (
  milestone_id uuid not null references public.milestones(id) on delete cascade,
  organization_id uuid not null references public.organizations(id) on delete restrict,
  responsibility_role text not null check (responsibility_role in ('primary', 'supporting')),
  created_at timestamptz not null default now(),
  primary key (milestone_id, organization_id)
);
create unique index if not exists milestone_organizations_one_primary
  on public.milestone_organizations(milestone_id)
  where responsibility_role = 'primary';

create table if not exists public.task_organizations (
  task_id uuid not null references public.tasks(id) on delete cascade,
  organization_id uuid not null references public.organizations(id) on delete restrict,
  responsibility_role text not null check (responsibility_role in ('primary', 'supporting')),
  created_at timestamptz not null default now(),
  primary key (task_id, organization_id)
);
create unique index if not exists task_organizations_one_primary
  on public.task_organizations(task_id)
  where responsibility_role = 'primary';
create index if not exists task_organizations_org_idx
  on public.task_organizations(organization_id, task_id);

create or replace function public.can_see_collaboration_project(
  target_project uuid,
  caller_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select caller_id is not null and (
    public.auth_role(caller_id) = 'super_admin'
    or public.is_project_member(target_project, caller_id)
    or exists (
      select 1
      from public.project_organizations participating
      where participating.project_id = target_project
        and (
          public.is_organization_approver(participating.organization_id, caller_id)
          or public.is_organization_member(participating.organization_id, caller_id)
        )
    )
  );
$$;

create or replace function public.can_manage_collaboration_project(
  target_project uuid,
  caller_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select caller_id is not null
    and public.auth_role(caller_id) <> 'super_admin'
    and exists (
      select 1
      from public.projects project
      join public.project_organizations owner_org
        on owner_org.project_id = project.id and owner_org.participation_role = 'owner'
      where project.id = target_project
        and (
          project.owner_id = caller_id
          or public.is_organization_approver(owner_org.organization_id, caller_id)
        )
    );
$$;

create or replace function public.can_see_project(target_project uuid, caller_id uuid)
returns boolean
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  project_row public.projects;
begin
  if caller_id is null then return false; end if;
  if public.auth_role(caller_id) = 'super_admin' then return true; end if;
  select * into project_row from public.projects where id = target_project;
  if not found then return false; end if;
  if project_row.source_collaboration_draft_id is not null then
    return public.can_see_collaboration_project(target_project, caller_id)
      or public.is_collaboration_participant(project_row.source_collaboration_draft_id, caller_id);
  end if;
  return project_row.owner_id = caller_id
    or public.is_project_member(target_project, caller_id)
    or exists (
      select 1 from public.tasks task
      where task.linked_project_id = target_project and task.deleted_at is null
        and (
          task.assigned_to = caller_id
          or task.recommendation_lead_id = caller_id
          or coalesce(to_jsonb(task.team_member_ids), '[]'::jsonb) ? caller_id::text
        )
    )
    or public.can_access_org(caller_id, project_row.org_id, 'read');
end;
$$;

create or replace function public.can_manage_project(target_project uuid, caller_id uuid)
returns boolean
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  project_row public.projects;
begin
  if caller_id is null or public.auth_role(caller_id) = 'super_admin' then return false; end if;
  select * into project_row from public.projects where id = target_project;
  if not found then return false; end if;
  if project_row.source_collaboration_draft_id is not null then
    return public.can_manage_collaboration_project(target_project, caller_id);
  end if;
  return project_row.owner_id = caller_id
    or project_row.created_by = caller_id
    or public.can_access_org(caller_id, project_row.org_id, 'manage');
end;
$$;

create or replace function public.can_see_task(target_task uuid, caller_id uuid)
returns boolean
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  task_row public.tasks;
begin
  if caller_id is null then return false; end if;
  if public.auth_role(caller_id) = 'super_admin' then return true; end if;
  select * into task_row from public.tasks where id = target_task and deleted_at is null;
  if not found then return false; end if;
  return task_row.assigned_to = caller_id
    or task_row.created_by = caller_id
    or task_row.recommendation_lead_id = caller_id
    or task_row.reviewer_id = caller_id
    or task_row.backup_reviewer_id = caller_id
    or coalesce(to_jsonb(task_row.team_member_ids), '[]'::jsonb) ? caller_id::text
    or (task_row.linked_project_id is not null and public.can_see_project(task_row.linked_project_id, caller_id))
    or (
      task_row.source_collaboration_draft_id is null
      and public.can_access_org(caller_id, task_row.org_id, 'read')
    );
end;
$$;

create or replace function public.can_manage_task(target_task uuid, caller_id uuid)
returns boolean
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  task_row public.tasks;
begin
  if caller_id is null or public.auth_role(caller_id) = 'super_admin' then return false; end if;
  select * into task_row from public.tasks where id = target_task and deleted_at is null;
  if not found then return false; end if;
  if task_row.source_collaboration_draft_id is not null then
    return task_row.recommendation_lead_id = caller_id
      or public.is_organization_approver(task_row.org_id, caller_id);
  end if;
  return task_row.created_by = caller_id
    or task_row.recommendation_lead_id = caller_id
    or public.can_access_org(caller_id, task_row.org_id, 'manage');
end;
$$;

-- Explicit and governance routes are authoritative and bypass ordinary
-- Head/Assistant reciprocal routing. Ordinary tasks retain their old behavior.
create or replace function public.route_organization_leadership_review()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  org_head uuid;
  org_assistant uuid;
  expected_reviewer uuid;
  expected_label text;
  reviewer_active boolean;
begin
  if coalesce(new.review_route_mode, 'organization_default') in ('explicit', 'governance') then
    return new;
  end if;
  if new.org_id is null or new.assigned_to is null then return new; end if;
  select head_user_id, assistant_head_user_id into org_head, org_assistant
  from public.organizations where id = new.org_id;
  if new.assigned_to = org_head then
    expected_reviewer := org_assistant; expected_label := 'Assistant Head';
  elsif new.assigned_to = org_assistant then
    expected_reviewer := org_head; expected_label := 'Head';
  else
    return new;
  end if;
  new.backup_reviewer_id := null;
  if expected_reviewer is not null then select is_active into reviewer_active from public.profiles where id = expected_reviewer; end if;
  if expected_reviewer is null or not coalesce(reviewer_active, false) then
    new.reviewer_id := null;
    if new.status = 'for_review' then
      raise exception 'Assign an active % for this organization before submitting leadership work', expected_label using errcode = '22023';
    end if;
    return new;
  end if;
  new.reviewer_id := expected_reviewer;
  return new;
end;
$$;

create or replace function public.guard_collaboration_task_staffing()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  candidate uuid;
  candidate_org uuid;
  caller uuid := auth.uid();
  caller_org uuid;
  changed_candidate uuid;
begin
  if new.source_collaboration_draft_id is null then return new; end if;
  if new.assigned_to is null then raise exception 'Collaboration tasks require a Task Leader' using errcode = '22023'; end if;
  if not (coalesce(new.team_member_ids, '{}'::uuid[]) @> array[new.assigned_to]) then
    raise exception 'Task Leader must belong to the selected team' using errcode = '22023';
  end if;
  foreach candidate in array coalesce(new.team_member_ids, '{}'::uuid[]) loop
    select org_id into candidate_org from public.profiles where id = candidate and is_active;
    if candidate_org is null or not exists (
      select 1 from public.proposal_collaboration_orgs eligible
      where eligible.draft_id = new.source_collaboration_draft_id
        and eligible.org_id = candidate_org and eligible.staffing_enabled
    ) then
      raise exception 'Every collaboration team member must be active and belong to a staffing-enabled participating organization'
      using errcode = '22023';
    end if;
  end loop;
  if tg_op = 'UPDATE' and (
    new.assigned_to is distinct from old.assigned_to
    or coalesce(new.team_member_ids, '{}'::uuid[]) is distinct from coalesce(old.team_member_ids, '{}'::uuid[])
  ) then
    select org_id into caller_org from public.profiles where id = caller and is_active;
    if new.assigned_to is distinct from old.assigned_to
       and not exists (select 1 from public.profiles where id = new.assigned_to and org_id = caller_org and is_active) then
      raise exception 'Changing a cross-organization Task Leader requires approval from that employee''s organization'
        using errcode = '42501';
    end if;
    foreach changed_candidate in array (
      select coalesce(array_agg(member_id), '{}'::uuid[])
      from (
        (select unnest(coalesce(new.team_member_ids, '{}'::uuid[])) member_id
         except select unnest(coalesce(old.team_member_ids, '{}'::uuid[])))
        union
        (select unnest(coalesce(old.team_member_ids, '{}'::uuid[])) member_id
         except select unnest(coalesce(new.team_member_ids, '{}'::uuid[])))
      ) changes
    ) loop
      if not exists (select 1 from public.profiles where id = changed_candidate and org_id = caller_org) then
        raise exception 'Cross-organization staffing changes require approval from the employee''s organization'
          using errcode = '42501';
      end if;
    end loop;
  end if;
  if new.review_route_mode = 'governance' then
    if new.reviewer_id is null then raise exception 'Governed tasks require an active Board reviewer' using errcode = '22023'; end if;
    if new.reviewer_id = new.assigned_to or new.backup_reviewer_id = new.assigned_to then
      raise exception 'Task Leader cannot review their own Task' using errcode = '22023';
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists tasks_guard_collaboration_staffing on public.tasks;
create trigger tasks_guard_collaboration_staffing
before insert or update of assigned_to, team_member_ids, reviewer_id, backup_reviewer_id, review_route_mode
on public.tasks for each row execute function public.guard_collaboration_task_staffing();

alter table public.project_organizations enable row level security;
alter table public.milestone_organizations enable row level security;
alter table public.task_organizations enable row level security;
create policy project_organizations_read on public.project_organizations for select to authenticated using (public.can_see_project(project_id, auth.uid()));
create policy milestone_organizations_read on public.milestone_organizations for select to authenticated using (exists (select 1 from public.milestones milestone where milestone.id = milestone_id and public.can_see_project(milestone.project_id, auth.uid())));
create policy task_organizations_read on public.task_organizations for select to authenticated using (public.can_see_task(task_id, auth.uid()));

revoke all on function public.can_see_collaboration_project(uuid, uuid) from public, anon;
revoke all on function public.can_manage_collaboration_project(uuid, uuid) from public, anon;
grant execute on function public.can_see_collaboration_project(uuid, uuid) to authenticated;
grant execute on function public.can_manage_collaboration_project(uuid, uuid) to authenticated;
grant select on public.project_organizations to authenticated;
grant select on public.milestone_organizations to authenticated;
grant select on public.task_organizations to authenticated;

notify pgrst, 'reload schema';
