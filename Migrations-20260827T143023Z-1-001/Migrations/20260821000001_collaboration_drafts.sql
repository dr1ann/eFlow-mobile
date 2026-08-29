-- Persistent, revisioned collaboration drafts shared by AI import and manual planning.

create table if not exists public.proposal_collaboration_drafts (
  id uuid primary key default gen_random_uuid(),
  title text not null check (btrim(title) <> ''),
  owner_org_id uuid not null references public.organizations(id) on delete restrict,
  owner_user_id uuid not null references public.profiles(id) on delete restrict,
  source_type text not null check (source_type in ('ai_pdf', 'manual')),
  source_file_name text,
  source_file_path text,
  source_file_hash text,
  status text not null default 'draft'
    check (status in ('draft', 'in_review', 'changes_requested', 'ready_to_commit', 'committed', 'archived', 'deleted')),
  working_snapshot jsonb not null default '{}'::jsonb check (jsonb_typeof(working_snapshot) = 'object'),
  current_revision_id uuid,
  created_by uuid not null references public.profiles(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  archived_at timestamptz,
  deleted_at timestamptz,
  committed_at timestamptz
);

create table if not exists public.proposal_collaboration_revisions (
  id uuid primary key default gen_random_uuid(),
  draft_id uuid not null references public.proposal_collaboration_drafts(id) on delete cascade,
  revision_number int not null check (revision_number > 0),
  snapshot jsonb not null check (jsonb_typeof(snapshot) = 'object'),
  created_by uuid not null references public.profiles(id) on delete restrict,
  created_at timestamptz not null default now(),
  change_summary text not null default 'Draft updated',
  unique (draft_id, revision_number)
);

alter table public.proposal_collaboration_drafts
  drop constraint if exists proposal_collaboration_drafts_current_revision_id_fkey;
alter table public.proposal_collaboration_drafts
  add constraint proposal_collaboration_drafts_current_revision_id_fkey
  foreign key (current_revision_id)
  references public.proposal_collaboration_revisions(id)
  on delete set null;

create table if not exists public.proposal_collaboration_orgs (
  draft_id uuid not null references public.proposal_collaboration_drafts(id) on delete cascade,
  org_id uuid not null references public.organizations(id) on delete restrict,
  participation_role text not null
    check (participation_role in ('owner', 'participant', 'governance')),
  staffing_enabled boolean not null default true,
  requested_by uuid references public.profiles(id) on delete set null,
  requested_at timestamptz,
  created_at timestamptz not null default now(),
  primary key (draft_id, org_id)
);

create unique index if not exists proposal_collaboration_orgs_one_owner
  on public.proposal_collaboration_orgs(draft_id)
  where participation_role = 'owner';
create index if not exists proposal_collaboration_drafts_owner_org_idx
  on public.proposal_collaboration_drafts(owner_org_id, status, updated_at desc);
create index if not exists proposal_collaboration_orgs_org_idx
  on public.proposal_collaboration_orgs(org_id, participation_role, draft_id);
create index if not exists proposal_collaboration_revisions_draft_idx
  on public.proposal_collaboration_revisions(draft_id, revision_number desc);

drop trigger if exists proposal_collaboration_drafts_touch on public.proposal_collaboration_drafts;
create trigger proposal_collaboration_drafts_touch
before update on public.proposal_collaboration_drafts
for each row execute function public.touch_updated_at();

create or replace function public.is_collaboration_participant(
  target_draft uuid,
  caller_id uuid
)
returns boolean
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  draft_row public.proposal_collaboration_drafts;
begin
  if target_draft is null or caller_id is null then return false; end if;
  select * into draft_row
  from public.proposal_collaboration_drafts
  where id = target_draft and deleted_at is null;
  if not found then return false; end if;
  if public.auth_role(caller_id) = 'super_admin' then return true; end if;
  if draft_row.owner_user_id = caller_id
     or public.is_organization_approver(draft_row.owner_org_id, caller_id) then
    return true;
  end if;
  return exists (
    select 1
    from public.proposal_collaboration_orgs participating
    where participating.draft_id = target_draft
      and (
        public.is_organization_approver(participating.org_id, caller_id)
        or public.is_organization_member(participating.org_id, caller_id)
      )
  );
end;
$$;

create or replace function public.can_manage_collaboration_draft(
  target_draft uuid,
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
    from public.proposal_collaboration_drafts draft
    where draft.id = target_draft
      and draft.deleted_at is null
      and draft.status not in ('committed', 'deleted')
      and (
        draft.owner_user_id = caller_id
        or public.is_organization_approver(draft.owner_org_id, caller_id)
      )
      and public.auth_role(caller_id) <> 'super_admin'
  );
$$;

create or replace function public.create_collaboration_draft(
  p_title text,
  p_owner_org_id uuid,
  p_source_type text,
  p_source_file_name text,
  p_source_file_path text,
  p_source_file_hash text,
  p_snapshot jsonb
)
returns public.proposal_collaboration_drafts
language plpgsql
security definer
set search_path = public
as $$
declare
  caller uuid := auth.uid();
  caller_name text := '';
  draft_row public.proposal_collaboration_drafts;
  revision_row public.proposal_collaboration_revisions;
  organization_item jsonb;
  additional_org_id uuid;
  additional_role text;
begin
  if caller is null then raise exception 'Not authenticated' using errcode = '42501'; end if;
  if nullif(btrim(p_title), '') is null then raise exception 'Draft title is required' using errcode = '22023'; end if;
  if p_source_type not in ('ai_pdf', 'manual') then raise exception 'Invalid draft source' using errcode = '22023'; end if;
  if jsonb_typeof(coalesce(p_snapshot, '{}'::jsonb)) <> 'object' then raise exception 'Draft snapshot must be an object' using errcode = '22023'; end if;
  if not public.is_organization_approver(p_owner_org_id, caller) then
    raise exception 'Only the Head or Assistant Head may create a proposal for this organization'
      using errcode = '42501';
  end if;

  insert into public.proposal_collaboration_drafts (
    title, owner_org_id, owner_user_id, source_type,
    source_file_name, source_file_path, source_file_hash,
    working_snapshot, created_by
  ) values (
    btrim(p_title), p_owner_org_id, caller, p_source_type,
    nullif(btrim(p_source_file_name), ''), nullif(btrim(p_source_file_path), ''),
    nullif(btrim(p_source_file_hash), ''), coalesce(p_snapshot, '{}'::jsonb), caller
  ) returning * into draft_row;

  insert into public.proposal_collaboration_revisions (
    draft_id, revision_number, snapshot, created_by, change_summary
  ) values (
    draft_row.id, 1, draft_row.working_snapshot, caller, 'Initial draft'
  ) returning * into revision_row;

  update public.proposal_collaboration_drafts
  set current_revision_id = revision_row.id
  where id = draft_row.id
  returning * into draft_row;

  insert into public.proposal_collaboration_orgs (
    draft_id, org_id, participation_role, staffing_enabled, requested_by
  ) values (draft_row.id, p_owner_org_id, 'owner', true, caller);
  select coalesce(full_name, 'User') into caller_name from public.profiles where id = caller;

  -- The initial snapshot is authoritative for collaboration scope. Creating
  -- these rows in the same RPC prevents a persistent draft from being left
  -- half-configured if a second browser request fails.
  for organization_item in
    select value from jsonb_array_elements(coalesce(p_snapshot -> 'organizations', '[]'::jsonb))
  loop
    additional_org_id := nullif(organization_item ->> 'orgId', '')::uuid;
    additional_role := coalesce(nullif(organization_item ->> 'participationRole', ''), 'participant');
    if additional_org_id is null or additional_org_id = p_owner_org_id then continue; end if;
    if additional_role not in ('participant', 'governance') then
      raise exception 'Additional organizations must be participants or governance' using errcode = '22023';
    end if;
    if not exists (select 1 from public.organizations where id = additional_org_id and is_active) then
      raise exception 'A selected collaboration organization is not configured or active' using errcode = '22023';
    end if;
    insert into public.proposal_collaboration_orgs (
      draft_id, org_id, participation_role, staffing_enabled, requested_by
    ) values (
      draft_row.id, additional_org_id, additional_role,
      case when additional_role = 'governance'
        then coalesce((organization_item ->> 'staffingEnabled')::boolean, false)
        else coalesce((organization_item ->> 'staffingEnabled')::boolean, true)
      end,
      caller
    );
    insert into public.audit_events (actor_id, actor_name, entity_type, entity_id, action, after_data, org_id)
    values (caller, caller_name, 'collaboration_draft', draft_row.id::text,
      'collaboration.organization_added',
      jsonb_build_object('organizationId', additional_org_id, 'participationRole', additional_role), p_owner_org_id);
  end loop;

  insert into public.audit_events (
    actor_id, actor_name, entity_type, entity_id, action, after_data, org_id
  ) values (
    caller, caller_name, 'collaboration_draft', draft_row.id::text,
    'collaboration.draft_created',
    jsonb_build_object('title', draft_row.title, 'sourceType', draft_row.source_type, 'revision', 1),
    draft_row.owner_org_id
  );
  return draft_row;
end;
$$;

create or replace function public.save_collaboration_revision(
  p_draft_id uuid,
  p_snapshot jsonb,
  p_change_summary text default 'Draft updated'
)
returns public.proposal_collaboration_revisions
language plpgsql
security definer
set search_path = public
as $$
declare
  caller uuid := auth.uid();
  draft_row public.proposal_collaboration_drafts;
  current_row public.proposal_collaboration_revisions;
  revision_row public.proposal_collaboration_revisions;
  next_number int;
  caller_name text := '';
begin
  if not public.can_manage_collaboration_draft(p_draft_id, caller) then
    raise exception 'Only the owning organization may revise this draft' using errcode = '42501';
  end if;
  if jsonb_typeof(coalesce(p_snapshot, '{}'::jsonb)) <> 'object' then
    raise exception 'Draft snapshot must be an object' using errcode = '22023';
  end if;
  select * into draft_row from public.proposal_collaboration_drafts where id = p_draft_id for update;
  select * into current_row from public.proposal_collaboration_revisions where id = draft_row.current_revision_id;
  if found and current_row.snapshot = p_snapshot then return current_row; end if;

  select coalesce(max(revision_number), 0) + 1 into next_number
  from public.proposal_collaboration_revisions where draft_id = p_draft_id;
  insert into public.proposal_collaboration_revisions (
    draft_id, revision_number, snapshot, created_by, change_summary
  ) values (
    p_draft_id, next_number, p_snapshot, caller,
    coalesce(nullif(btrim(p_change_summary), ''), 'Draft updated')
  ) returning * into revision_row;

  update public.proposal_collaboration_drafts
  set working_snapshot = p_snapshot,
      current_revision_id = revision_row.id,
      status = case when status in ('in_review', 'ready_to_commit') then 'changes_requested' else status end
  where id = p_draft_id;

  select coalesce(full_name, 'User') into caller_name from public.profiles where id = caller;
  insert into public.audit_events (
    actor_id, actor_name, entity_type, entity_id, action, reason, after_data, org_id
  ) values (
    caller, caller_name, 'collaboration_revision', revision_row.id::text,
    'collaboration.revision_created', revision_row.change_summary,
    jsonb_build_object('draftId', p_draft_id, 'revision', next_number), draft_row.owner_org_id
  );
  return revision_row;
end;
$$;

-- Draft-mode autosave is deliberately not an immutable approval revision.
-- The working snapshot is finalized into a revision when review is requested,
-- preventing every keystroke from generating governance history while still
-- surviving a closed browser.
create or replace function public.autosave_collaboration_draft(
  p_draft_id uuid,
  p_title text,
  p_snapshot jsonb
)
returns public.proposal_collaboration_drafts
language plpgsql
security definer
set search_path = public
as $$
declare
  caller uuid := auth.uid();
  draft_row public.proposal_collaboration_drafts;
  organization_item jsonb;
  target_org uuid;
  target_role text;
  previous_org_ids uuid[] := '{}'::uuid[];
  previous_org_id uuid;
  caller_name text := '';
begin
  if not public.can_manage_collaboration_draft(p_draft_id, caller) then
    raise exception 'Only the owning organization may autosave this draft' using errcode = '42501';
  end if;
  if nullif(btrim(p_title), '') is null or jsonb_typeof(coalesce(p_snapshot, '{}'::jsonb)) <> 'object' then
    raise exception 'Draft title and snapshot are required' using errcode = '22023';
  end if;
  select * into draft_row from public.proposal_collaboration_drafts where id = p_draft_id for update;
  if draft_row.status <> 'draft' then
    raise exception 'Autosave is available only before collaboration review starts' using errcode = '22023';
  end if;
  select coalesce(array_agg(org_id), '{}'::uuid[]) into previous_org_ids
  from public.proposal_collaboration_orgs
  where draft_id = p_draft_id and participation_role <> 'owner';
  select coalesce(full_name, 'Owner') into caller_name from public.profiles where id = caller;

  delete from public.proposal_collaboration_orgs
  where draft_id = p_draft_id and participation_role <> 'owner';
  for organization_item in
    select value from jsonb_array_elements(coalesce(p_snapshot -> 'organizations', '[]'::jsonb))
  loop
    target_org := nullif(organization_item ->> 'orgId', '')::uuid;
    target_role := coalesce(nullif(organization_item ->> 'participationRole', ''), 'participant');
    if target_org is null or target_org = draft_row.owner_org_id then continue; end if;
    if target_role not in ('participant', 'governance')
       or not exists (select 1 from public.organizations where id = target_org and is_active) then
      raise exception 'Autosave contains an invalid collaboration organization' using errcode = '22023';
    end if;
    insert into public.proposal_collaboration_orgs (
      draft_id, org_id, participation_role, staffing_enabled, requested_by
    ) values (
      p_draft_id, target_org, target_role,
      case when target_role = 'governance'
        then coalesce((organization_item ->> 'staffingEnabled')::boolean, false)
        else coalesce((organization_item ->> 'staffingEnabled')::boolean, true)
      end,
      caller
    );
    if not (previous_org_ids @> array[target_org]) then
      insert into public.audit_events (actor_id, actor_name, entity_type, entity_id, action, after_data, org_id)
      values (caller, caller_name, 'collaboration_draft', p_draft_id::text,
        'collaboration.organization_added',
        jsonb_build_object('organizationId', target_org, 'participationRole', target_role), draft_row.owner_org_id);
    end if;
  end loop;

  foreach previous_org_id in array previous_org_ids loop
    if not exists (
      select 1 from jsonb_array_elements(coalesce(p_snapshot -> 'organizations', '[]'::jsonb)) selected
      where nullif(selected ->> 'orgId', '')::uuid = previous_org_id
    ) then
      insert into public.audit_events (actor_id, actor_name, entity_type, entity_id, action, after_data, org_id)
      values (caller, caller_name, 'collaboration_draft', p_draft_id::text,
        'collaboration.organization_removed',
        jsonb_build_object('organizationId', previous_org_id), draft_row.owner_org_id);
    end if;
  end loop;

  update public.proposal_collaboration_drafts
  set title = btrim(p_title), working_snapshot = p_snapshot
  where id = p_draft_id
  returning * into draft_row;
  return draft_row;
end;
$$;

create or replace function public.set_collaboration_organizations(
  p_draft_id uuid,
  p_organizations jsonb,
  p_snapshot jsonb,
  p_change_summary text default 'Collaboration organizations updated'
)
returns public.proposal_collaboration_revisions
language plpgsql
security definer
set search_path = public
as $$
declare
  caller uuid := auth.uid();
  draft_row public.proposal_collaboration_drafts;
  item jsonb;
  target_org uuid;
  target_role text;
  previous_org_ids uuid[] := '{}'::uuid[];
  previous_org_id uuid;
  caller_name text := '';
begin
  if not public.can_manage_collaboration_draft(p_draft_id, caller) then
    raise exception 'Only the owning organization may change collaboration scope' using errcode = '42501';
  end if;
  if jsonb_typeof(coalesce(p_organizations, '[]'::jsonb)) <> 'array' then
    raise exception 'Organizations must be an array' using errcode = '22023';
  end if;
  select * into draft_row from public.proposal_collaboration_drafts where id = p_draft_id for update;
  select coalesce(array_agg(org_id), '{}'::uuid[]) into previous_org_ids
  from public.proposal_collaboration_orgs
  where draft_id = p_draft_id and participation_role <> 'owner';
  select coalesce(full_name, 'Owner') into caller_name from public.profiles where id = caller;

  delete from public.proposal_collaboration_orgs
  where draft_id = p_draft_id and participation_role <> 'owner';

  for item in select value from jsonb_array_elements(p_organizations) loop
    target_org := nullif(item ->> 'orgId', '')::uuid;
    target_role := coalesce(nullif(item ->> 'participationRole', ''), 'participant');
    if target_org = draft_row.owner_org_id then continue; end if;
    if target_role not in ('participant', 'governance') then
      raise exception 'Additional organizations must be participants or governance' using errcode = '22023';
    end if;
    if not exists (select 1 from public.organizations where id = target_org and is_active) then
      raise exception 'A selected organization is not configured or active' using errcode = '22023';
    end if;
    insert into public.proposal_collaboration_orgs (
      draft_id, org_id, participation_role, staffing_enabled, requested_by
    ) values (
      p_draft_id, target_org, target_role,
      case when target_role = 'governance' then coalesce((item ->> 'staffingEnabled')::boolean, false) else coalesce((item ->> 'staffingEnabled')::boolean, true) end,
      caller
    ) on conflict (draft_id, org_id) do update
      set participation_role = excluded.participation_role,
          staffing_enabled = excluded.staffing_enabled,
          requested_by = excluded.requested_by;
    if not (previous_org_ids @> array[target_org]) then
      insert into public.audit_events (actor_id, actor_name, entity_type, entity_id, action, after_data, org_id)
      values (caller, caller_name, 'collaboration_draft', p_draft_id::text,
        'collaboration.organization_added',
        jsonb_build_object('organizationId', target_org, 'participationRole', target_role), draft_row.owner_org_id);
    end if;
  end loop;

  foreach previous_org_id in array previous_org_ids loop
    if not exists (
      select 1 from jsonb_array_elements(p_organizations) selected
      where nullif(selected ->> 'orgId', '')::uuid = previous_org_id
    ) then
      insert into public.audit_events (actor_id, actor_name, entity_type, entity_id, action, after_data, org_id)
      values (caller, caller_name, 'collaboration_draft', p_draft_id::text,
        'collaboration.organization_removed',
        jsonb_build_object('organizationId', previous_org_id), draft_row.owner_org_id);
    end if;
  end loop;

  return public.save_collaboration_revision(p_draft_id, p_snapshot, p_change_summary);
end;
$$;

create or replace function public.soft_delete_collaboration_draft(
  p_draft_id uuid,
  p_reason text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  caller uuid := auth.uid();
  draft_row public.proposal_collaboration_drafts;
  caller_name text := '';
begin
  if not public.can_manage_collaboration_draft(p_draft_id, caller) then
    raise exception 'Only the owning organization may delete this draft' using errcode = '42501';
  end if;
  if nullif(btrim(p_reason), '') is null then raise exception 'Deletion reason is required' using errcode = '22023'; end if;
  update public.proposal_collaboration_drafts
  set status = 'deleted', deleted_at = now()
  where id = p_draft_id and status <> 'committed'
  returning * into draft_row;
  if not found then raise exception 'Committed drafts cannot be deleted' using errcode = '22023'; end if;
  select coalesce(full_name, 'User') into caller_name from public.profiles where id = caller;
  insert into public.audit_events (actor_id, actor_name, entity_type, entity_id, action, reason, org_id)
  values (caller, caller_name, 'collaboration_draft', p_draft_id::text, 'collaboration.deleted', btrim(p_reason), draft_row.owner_org_id);
end;
$$;

create or replace function public.set_collaboration_source_document(
  p_draft_id uuid,
  p_source_file_name text,
  p_source_file_path text,
  p_source_file_hash text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  caller uuid := auth.uid();
  draft_row public.proposal_collaboration_drafts;
  caller_name text := '';
begin
  if not public.can_manage_collaboration_draft(p_draft_id, caller) then
    raise exception 'Only the owning organization may attach the source document' using errcode = '42501';
  end if;
  select * into draft_row from public.proposal_collaboration_drafts where id = p_draft_id for update;
  update public.proposal_collaboration_drafts
  set source_file_name = nullif(btrim(p_source_file_name), ''),
      source_file_path = nullif(btrim(p_source_file_path), ''),
      source_file_hash = nullif(btrim(p_source_file_hash), '')
  where id = p_draft_id;
  select coalesce(full_name, 'Owner') into caller_name from public.profiles where id = caller;
  insert into public.audit_events (actor_id, actor_name, entity_type, entity_id, action, after_data, org_id)
  values (
    caller, caller_name, 'collaboration_draft', p_draft_id::text, 'collaboration.source_document_attached',
    jsonb_build_object('fileName', nullif(btrim(p_source_file_name), ''), 'sha256', nullif(btrim(p_source_file_hash), '')),
    draft_row.owner_org_id
  );
end;
$$;

alter table public.proposal_collaboration_drafts enable row level security;
alter table public.proposal_collaboration_revisions enable row level security;
alter table public.proposal_collaboration_orgs enable row level security;

drop policy if exists collaboration_drafts_read on public.proposal_collaboration_drafts;
create policy collaboration_drafts_read on public.proposal_collaboration_drafts
for select to authenticated using (public.is_collaboration_participant(id, auth.uid()));
drop policy if exists collaboration_revisions_read on public.proposal_collaboration_revisions;
create policy collaboration_revisions_read on public.proposal_collaboration_revisions
for select to authenticated using (public.is_collaboration_participant(draft_id, auth.uid()));
drop policy if exists collaboration_orgs_read on public.proposal_collaboration_orgs;
create policy collaboration_orgs_read on public.proposal_collaboration_orgs
for select to authenticated using (public.is_collaboration_participant(draft_id, auth.uid()));

revoke all on function public.is_collaboration_participant(uuid, uuid) from public, anon;
revoke all on function public.can_manage_collaboration_draft(uuid, uuid) from public, anon;
revoke all on function public.create_collaboration_draft(text, uuid, text, text, text, text, jsonb) from public, anon;
revoke all on function public.autosave_collaboration_draft(uuid, text, jsonb) from public, anon;
revoke all on function public.save_collaboration_revision(uuid, jsonb, text) from public, anon;
revoke all on function public.set_collaboration_organizations(uuid, jsonb, jsonb, text) from public, anon;
revoke all on function public.soft_delete_collaboration_draft(uuid, text) from public, anon;
revoke all on function public.set_collaboration_source_document(uuid, text, text, text) from public, anon;
grant execute on function public.is_collaboration_participant(uuid, uuid) to authenticated;
grant execute on function public.can_manage_collaboration_draft(uuid, uuid) to authenticated;
grant execute on function public.create_collaboration_draft(text, uuid, text, text, text, text, jsonb) to authenticated;
grant execute on function public.autosave_collaboration_draft(uuid, text, jsonb) to authenticated;
grant execute on function public.save_collaboration_revision(uuid, jsonb, text) to authenticated;
grant execute on function public.set_collaboration_organizations(uuid, jsonb, jsonb, text) to authenticated;
grant execute on function public.soft_delete_collaboration_draft(uuid, text) to authenticated;
grant execute on function public.set_collaboration_source_document(uuid, text, text, text) to authenticated;
grant select on public.proposal_collaboration_drafts to authenticated;
grant select on public.proposal_collaboration_revisions to authenticated;
grant select on public.proposal_collaboration_orgs to authenticated;

notify pgrst, 'reload schema';
