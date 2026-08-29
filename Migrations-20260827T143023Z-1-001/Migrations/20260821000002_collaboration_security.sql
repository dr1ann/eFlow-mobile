-- Collaboration review, discussion, structured changes, approvals, readiness,
-- notifications, and private source-document access.

create table if not exists public.proposal_collaboration_messages (
  id uuid primary key default gen_random_uuid(),
  draft_id uuid not null references public.proposal_collaboration_drafts(id) on delete cascade,
  revision_id uuid references public.proposal_collaboration_revisions(id) on delete set null,
  author_id uuid references public.profiles(id) on delete set null,
  author_org_id uuid references public.organizations(id) on delete set null,
  message text not null check (btrim(message) <> ''),
  message_type text not null default 'comment'
    check (message_type in ('comment', 'system', 'change_request_comment')),
  target_type text check (target_type in ('proposal', 'program', 'project', 'activity', 'task', 'staff_assignment')),
  target_key text,
  created_at timestamptz not null default now()
);

create table if not exists public.proposal_collaboration_change_requests (
  id uuid primary key default gen_random_uuid(),
  draft_id uuid not null references public.proposal_collaboration_drafts(id) on delete cascade,
  revision_id uuid not null references public.proposal_collaboration_revisions(id) on delete restrict,
  requested_by uuid not null references public.profiles(id) on delete restrict,
  requesting_org_id uuid not null references public.organizations(id) on delete restrict,
  target_type text not null check (target_type in ('proposal', 'program', 'project', 'activity', 'task', 'staff_assignment')),
  target_key text not null,
  reason text not null check (btrim(reason) <> ''),
  proposed_change jsonb not null default '{}'::jsonb,
  status text not null default 'open'
    check (status in ('open', 'accepted', 'rejected', 'withdrawn')),
  resolved_by uuid references public.profiles(id) on delete set null,
  resolved_at timestamptz,
  created_at timestamptz not null default now()
);

create table if not exists public.proposal_collaboration_approvals (
  id uuid primary key default gen_random_uuid(),
  draft_id uuid not null references public.proposal_collaboration_drafts(id) on delete cascade,
  revision_id uuid not null references public.proposal_collaboration_revisions(id) on delete restrict,
  organization_id uuid not null references public.organizations(id) on delete restrict,
  decision text not null check (decision in ('approved', 'changes_requested', 'declined')),
  approved_by uuid not null references public.profiles(id) on delete restrict,
  reason text,
  created_at timestamptz not null default now(),
  unique (revision_id, organization_id)
);

create or replace function public.auto_accept_collaboration_owner()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  should_audit boolean := false;
begin
  if new.current_revision_id is not null
     and new.status in ('in_review', 'changes_requested', 'ready_to_commit') then
    select not exists (
      select 1 from public.proposal_collaboration_approvals approval
      where approval.revision_id = new.current_revision_id
        and approval.organization_id = new.owner_org_id
        and approval.decision = 'approved'
    ) into should_audit;
    insert into public.proposal_collaboration_approvals (
      draft_id, revision_id, organization_id, decision, approved_by, reason
    ) values (
      new.id, new.current_revision_id, new.owner_org_id, 'approved', new.owner_user_id,
      'Owner organization accepted automatically when collaboration review was requested.'
    )
    on conflict (revision_id, organization_id) do update
      set decision = 'approved', approved_by = excluded.approved_by,
          reason = excluded.reason, created_at = now();
    if should_audit then
      insert into public.audit_events (actor_id, actor_name, entity_type, entity_id, action, reason, after_data, org_id)
      values (
        new.owner_user_id, coalesce((select full_name from public.profiles where id = new.owner_user_id), 'Owner'),
        'collaboration_approval', new.current_revision_id::text, 'collaboration.owner_auto_accepted',
        'Owner organization accepted automatically when collaboration review was requested.',
        jsonb_build_object('draftId', new.id, 'revisionId', new.current_revision_id, 'organizationId', new.owner_org_id),
        new.owner_org_id
      );
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists proposal_collaboration_owner_auto_accept on public.proposal_collaboration_drafts;
create trigger proposal_collaboration_owner_auto_accept
after update of status, current_revision_id on public.proposal_collaboration_drafts
for each row execute function public.auto_accept_collaboration_owner();

create or replace function public.guard_collaboration_owner_decision()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if exists (
    select 1 from public.proposal_collaboration_orgs participant
    where participant.draft_id = new.draft_id
      and participant.org_id = new.organization_id
      and participant.participation_role = 'owner'
  ) and (
    pg_trigger_depth() < 2
    or new.decision <> 'approved'
    or new.approved_by <> (select draft.owner_user_id from public.proposal_collaboration_drafts draft where draft.id = new.draft_id)
  ) then
    raise exception 'The owning organization is accepted automatically and cannot submit a review decision' using errcode = '42501';
  end if;
  return new;
end;
$$;

drop trigger if exists proposal_collaboration_owner_decision_guard on public.proposal_collaboration_approvals;
create trigger proposal_collaboration_owner_decision_guard
before insert or update on public.proposal_collaboration_approvals
for each row execute function public.guard_collaboration_owner_decision();

create index if not exists collaboration_messages_draft_idx
  on public.proposal_collaboration_messages(draft_id, created_at);
create index if not exists collaboration_changes_draft_idx
  on public.proposal_collaboration_change_requests(draft_id, status, created_at desc);
create index if not exists collaboration_approvals_draft_idx
  on public.proposal_collaboration_approvals(draft_id, revision_id, organization_id);

create or replace function public.organization_approver_ids(target_organization uuid)
returns setof uuid
language sql
stable
security definer
set search_path = public
as $$
  select approver_id
  from (
    select organization.head_user_id as approver_id
    from public.organizations organization
    where organization.id = target_organization and organization.is_active
    union
    select organization.assistant_head_user_id
    from public.organizations organization
    where organization.id = target_organization and organization.is_active
    union
    select membership.user_id
    from public.organization_memberships membership
    join public.profiles profile on profile.id = membership.user_id and profile.is_active
    where membership.organization_id = target_organization
      and membership.membership_role in ('primary_approver', 'backup_approver')
  ) approvers
  where approver_id is not null;
$$;

create or replace function public.collaboration_readiness(target_draft uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  draft_row public.proposal_collaboration_drafts;
  required_count int := 0;
  approved_count int := 0;
  open_change_count int := 0;
  missing_approvers int := 0;
  selected_task_count int := 0;
  invalid_task_count int := 0;
  ready boolean := false;
begin
  select * into draft_row from public.proposal_collaboration_drafts where id = target_draft and deleted_at is null;
  if not found then return jsonb_build_object('ready', false, 'blockers', jsonb_build_array('Draft not found')); end if;

  select count(*) into required_count from public.proposal_collaboration_orgs where draft_id = target_draft and participation_role <> 'owner';
  select count(*) into approved_count
  from public.proposal_collaboration_orgs participating
  join public.proposal_collaboration_approvals approval
    on approval.draft_id = participating.draft_id
   and approval.organization_id = participating.org_id
   and approval.revision_id = draft_row.current_revision_id
   and approval.decision = 'approved'
  where participating.draft_id = target_draft and participating.participation_role <> 'owner';
  select count(*) into open_change_count
  from public.proposal_collaboration_change_requests
  where draft_id = target_draft and status = 'open';
  select count(*) into missing_approvers
  from public.proposal_collaboration_orgs participating
  where participating.draft_id = target_draft
    and participating.participation_role <> 'owner'
    and not exists (select 1 from public.organization_approver_ids(participating.org_id));

  select count(*) into selected_task_count
  from jsonb_array_elements(coalesce(draft_row.working_snapshot -> 'tasks', '[]'::jsonb)) task
  where coalesce((task ->> 'enabled')::boolean, true);

  select count(*) into invalid_task_count
  from jsonb_array_elements(coalesce(draft_row.working_snapshot -> 'tasks', '[]'::jsonb)) task
  where coalesce((task ->> 'enabled')::boolean, true)
    and (
      nullif(btrim(task ->> 'title'), '') is null
      or nullif(task ->> 'leadMemberId', '') is null
      or not (coalesce(task -> 'assignedMemberIds', '[]'::jsonb) ? coalesce(task ->> 'leadMemberId', ''))
      or not exists (
        select 1 from public.proposal_collaboration_orgs eligible
        where eligible.draft_id = target_draft
          and eligible.org_id = coalesce(nullif(task ->> 'primaryOrgId', '')::uuid, draft_row.owner_org_id)
          and eligible.staffing_enabled
      )
      or not exists (
        select 1 from public.proposal_collaboration_orgs eligible
        where eligible.draft_id = target_draft
          and eligible.org_id = coalesce(nullif(task ->> 'activityPrimaryOrgId', '')::uuid, draft_row.owner_org_id)
          and eligible.staffing_enabled
      )
      or exists (
        select 1
        from jsonb_array_elements_text(coalesce(task -> 'assignedMemberIds', '[]'::jsonb)) member(raw_id)
        left join public.profiles profile on profile.id = member.raw_id::uuid and profile.is_active
        where profile.id is null or not exists (
          select 1 from public.proposal_collaboration_orgs eligible
          where eligible.draft_id = target_draft and eligible.org_id = profile.org_id and eligible.staffing_enabled
        )
      )
      or exists (
        select 1 from jsonb_array_elements_text(coalesce(task -> 'supportingOrgIds', '[]'::jsonb)) supporting(raw_id)
        where supporting.raw_id::uuid = coalesce(nullif(task ->> 'primaryOrgId', '')::uuid, draft_row.owner_org_id)
          or not exists (select 1 from public.proposal_collaboration_orgs participating where participating.draft_id = target_draft and participating.org_id = supporting.raw_id::uuid)
      )
      or exists (
        select 1 from jsonb_array_elements_text(coalesce(task -> 'activitySupportingOrgIds', '[]'::jsonb)) supporting(raw_id)
        where supporting.raw_id::uuid = coalesce(nullif(task ->> 'activityPrimaryOrgId', '')::uuid, draft_row.owner_org_id)
          or not exists (select 1 from public.proposal_collaboration_orgs participating where participating.draft_id = target_draft and participating.org_id = supporting.raw_id::uuid)
      )
      or (
        exists (select 1 from public.proposal_collaboration_orgs where draft_id = target_draft and participation_role = 'governance')
        and not exists (
          select 1
          from (
            select org_id from public.proposal_collaboration_orgs
            where draft_id = target_draft and participation_role = 'governance'
            order by created_at limit 1
          ) governance
          cross join lateral public.organization_approver_ids(governance.org_id) approver_id
          where approver_id <> nullif(task ->> 'leadMemberId', '')::uuid
        )
      )
    );

  ready := draft_row.current_revision_id is not null
    and selected_task_count > 0
    and invalid_task_count = 0
    and approved_count = required_count
    and open_change_count = 0
    and missing_approvers = 0
    and draft_row.status not in ('committed', 'archived', 'deleted');

  return jsonb_build_object(
    'ready', ready,
    'requiredOrganizations', required_count,
    'approvedOrganizations', approved_count,
    'openChangeRequests', open_change_count,
    'missingApprovers', missing_approvers,
    'selectedTasks', selected_task_count,
    'invalidTasks', invalid_task_count,
    'currentRevisionId', draft_row.current_revision_id,
    'blockers', (
      select coalesce(jsonb_agg(blocker), '[]'::jsonb)
      from (values
        (case when draft_row.current_revision_id is null then 'Publish a revision' end),
        (case when approved_count < required_count then (required_count - approved_count)::text || ' organization approval(s) pending' end),
        (case when open_change_count > 0 then open_change_count::text || ' unresolved change request(s)' end),
        (case when missing_approvers > 0 then missing_approvers::text || ' organization(s) have no configured approver' end),
        (case when selected_task_count = 0 then 'Select at least one task' end),
        (case when invalid_task_count > 0 then invalid_task_count::text || ' task(s) have incomplete staffing, responsibility, or review routing' end)
      ) blockers(blocker)
      where blocker is not null
    )
  );
end;
$$;

create or replace function public.refresh_collaboration_readiness(target_draft uuid)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  readiness jsonb;
  was_ready boolean;
  now_ready boolean;
  draft_row public.proposal_collaboration_drafts;
begin
  select * into draft_row from public.proposal_collaboration_drafts where id = target_draft for update;
  if not found then return false; end if;
  was_ready := draft_row.status = 'ready_to_commit';
  readiness := public.collaboration_readiness(target_draft);
  now_ready := coalesce((readiness ->> 'ready')::boolean, false);
  update public.proposal_collaboration_drafts
  set status = case
    when now_ready then 'ready_to_commit'
    when status in ('ready_to_commit', 'in_review') then 'in_review'
    else status
  end
  where id = target_draft;

  if now_ready and not was_ready then
    insert into public.notifications (
      user_id, type, title, message, proposal_id, org_id, entity_type
    ) values (
      draft_row.owner_user_id, 'collaboration_ready', 'Proposal ready to commit',
      'All required organizations approved "' || draft_row.title || '". The proposal is ready for atomic commit.',
      target_draft::text, draft_row.owner_org_id, 'collaboration_draft'
    );
    insert into public.audit_events (actor_name, entity_type, entity_id, action, after_data, org_id)
    values ('eFlow', 'collaboration_draft', target_draft::text, 'collaboration.ready_to_commit', readiness, draft_row.owner_org_id);
  end if;
  return now_ready;
end;
$$;

create or replace function public.request_collaboration_review(p_draft_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  caller uuid := auth.uid();
  draft_row public.proposal_collaboration_drafts;
  current_revision public.proposal_collaboration_revisions;
  finalized_revision public.proposal_collaboration_revisions;
  next_revision_number int;
  caller_name text := '';
begin
  if not public.can_manage_collaboration_draft(p_draft_id, caller) then
    raise exception 'Only the owning organization may request collaboration review' using errcode = '42501';
  end if;
  select * into draft_row from public.proposal_collaboration_drafts where id = p_draft_id for update;
  if draft_row.current_revision_id is null then raise exception 'Publish a revision before requesting review' using errcode = '22023'; end if;
  select * into current_revision from public.proposal_collaboration_revisions where id = draft_row.current_revision_id;
  if current_revision.snapshot is distinct from draft_row.working_snapshot then
    select coalesce(max(revision_number), 0) + 1 into next_revision_number
    from public.proposal_collaboration_revisions where draft_id = p_draft_id;
    insert into public.proposal_collaboration_revisions (draft_id, revision_number, snapshot, created_by, change_summary)
    values (p_draft_id, next_revision_number, draft_row.working_snapshot, caller, 'Draft finalized for collaboration review')
    returning * into finalized_revision;
    update public.proposal_collaboration_drafts set current_revision_id = finalized_revision.id where id = p_draft_id;
    draft_row.current_revision_id := finalized_revision.id;
    insert into public.audit_events (actor_id, actor_name, entity_type, entity_id, action, reason, after_data, org_id)
    values (caller, coalesce((select full_name from public.profiles where id = caller), 'Owner'),
      'collaboration_revision', finalized_revision.id::text, 'collaboration.revision_created',
      finalized_revision.change_summary,
      jsonb_build_object('draftId', p_draft_id, 'revision', next_revision_number), draft_row.owner_org_id);
  end if;
  update public.proposal_collaboration_drafts set status = 'in_review' where id = p_draft_id;
  update public.proposal_collaboration_orgs set requested_by = caller, requested_at = now() where draft_id = p_draft_id;
  select coalesce(full_name, 'Owner') into caller_name from public.profiles where id = caller;

  insert into public.notifications (
    user_id, type, title, message, actor_id, actor_name, proposal_id, org_id, entity_type
  )
  select approver_id, 'collaboration_request', 'Inter-department collaboration request',
    caller_name || ' requested review of "' || draft_row.title || '".',
    caller, caller_name, p_draft_id::text, participating.org_id, 'collaboration_draft'
  from public.proposal_collaboration_orgs participating
  cross join lateral public.organization_approver_ids(participating.org_id) approver_id
  where participating.draft_id = p_draft_id
    and participating.participation_role <> 'owner'
    and approver_id <> caller;

  insert into public.audit_events (actor_id, actor_name, entity_type, entity_id, action, after_data, org_id)
  values (caller, caller_name, 'collaboration_draft', p_draft_id::text, 'collaboration.review_requested',
    jsonb_build_object('revisionId', draft_row.current_revision_id), draft_row.owner_org_id);
  perform public.refresh_collaboration_readiness(p_draft_id);
end;
$$;

create or replace function public.send_collaboration_message(
  p_draft_id uuid,
  p_message text,
  p_target_type text default 'proposal',
  p_target_key text default null,
  p_message_type text default 'comment'
)
returns public.proposal_collaboration_messages
language plpgsql
security definer
set search_path = public
as $$
declare
  caller uuid := auth.uid();
  profile_row public.profiles;
  draft_row public.proposal_collaboration_drafts;
  message_row public.proposal_collaboration_messages;
begin
  if not public.is_collaboration_participant(p_draft_id, caller) then raise exception 'Not allowed to participate in this collaboration' using errcode = '42501'; end if;
  if nullif(btrim(p_message), '') is null then raise exception 'Message is required' using errcode = '22023'; end if;
  if p_message_type not in ('comment', 'system', 'change_request_comment') or p_message_type = 'system' then
    raise exception 'Invalid message type' using errcode = '22023';
  end if;
  select * into profile_row from public.profiles where id = caller and is_active;
  select * into draft_row from public.proposal_collaboration_drafts where id = p_draft_id;
  insert into public.proposal_collaboration_messages (
    draft_id, revision_id, author_id, author_org_id, message, message_type, target_type, target_key
  ) values (
    p_draft_id, draft_row.current_revision_id, caller, profile_row.org_id,
    btrim(p_message), p_message_type, p_target_type, nullif(btrim(p_target_key), '')
  ) returning * into message_row;

  insert into public.notifications (user_id, type, title, message, actor_id, actor_name, proposal_id, org_id, entity_type)
  select distinct approver_id, 'collaboration_message', 'New collaboration message',
    profile_row.full_name || ' commented on "' || draft_row.title || '".',
    caller, profile_row.full_name, p_draft_id::text, participating.org_id, 'collaboration_draft'
  from public.proposal_collaboration_orgs participating
  cross join lateral public.organization_approver_ids(participating.org_id) approver_id
  where participating.draft_id = p_draft_id and approver_id <> caller;
  insert into public.audit_events (actor_id, actor_name, entity_type, entity_id, action, after_data, org_id)
  values (caller, profile_row.full_name, 'collaboration_message', message_row.id::text,
    'collaboration.message_sent',
    jsonb_build_object('draftId', p_draft_id, 'revisionId', draft_row.current_revision_id,
      'targetType', p_target_type, 'targetKey', p_target_key), draft_row.owner_org_id);
  return message_row;
end;
$$;

create or replace function public.create_collaboration_change_request(
  p_draft_id uuid,
  p_target_type text,
  p_target_key text,
  p_reason text,
  p_proposed_change jsonb default '{}'::jsonb,
  p_organization_id uuid default null
)
returns public.proposal_collaboration_change_requests
language plpgsql
security definer
set search_path = public
as $$
declare
  caller uuid := auth.uid();
  profile_row public.profiles;
  draft_row public.proposal_collaboration_drafts;
  request_row public.proposal_collaboration_change_requests;
  acting_org uuid;
begin
  if not public.is_collaboration_participant(p_draft_id, caller) or public.auth_role(caller) = 'super_admin' then
    raise exception 'Not allowed to request changes' using errcode = '42501';
  end if;
  if nullif(btrim(p_reason), '') is null or nullif(btrim(p_target_key), '') is null then raise exception 'Change target and reason are required' using errcode = '22023'; end if;
  select * into profile_row from public.profiles where id = caller and is_active;
  acting_org := p_organization_id;
  if acting_org is null and exists (
    select 1 from public.proposal_collaboration_orgs participating
    where participating.draft_id = p_draft_id and participating.org_id = profile_row.org_id
      and public.is_organization_approver(participating.org_id, caller)
  ) then acting_org := profile_row.org_id; end if;
  if acting_org is null then
    select participating.org_id into acting_org
    from public.proposal_collaboration_orgs participating
    join public.organization_memberships membership
      on membership.organization_id = participating.org_id and membership.user_id = caller
    where participating.draft_id = p_draft_id
      and membership.membership_role in ('primary_approver', 'backup_approver')
    order by case when participating.participation_role = 'governance' then 0 else 1 end
    limit 1;
  end if;
  if acting_org is null or not public.is_organization_approver(acting_org, caller)
     or not exists (select 1 from public.proposal_collaboration_orgs where draft_id = p_draft_id and org_id = acting_org) then
    raise exception 'Only an organization approver may request a formal change' using errcode = '42501';
  end if;
  select * into draft_row from public.proposal_collaboration_drafts where id = p_draft_id;
  insert into public.proposal_collaboration_change_requests (
    draft_id, revision_id, requested_by, requesting_org_id,
    target_type, target_key, reason, proposed_change
  ) values (
    p_draft_id, draft_row.current_revision_id, caller,
    acting_org,
    p_target_type, btrim(p_target_key), btrim(p_reason), coalesce(p_proposed_change, '{}'::jsonb)
  ) returning * into request_row;
  update public.proposal_collaboration_drafts set status = 'changes_requested' where id = p_draft_id;
  perform public.refresh_collaboration_readiness(p_draft_id);
  insert into public.notifications (user_id, type, title, message, actor_id, actor_name, proposal_id, org_id, entity_type)
  values (draft_row.owner_user_id, 'collaboration_change', 'Proposal changes requested',
    profile_row.full_name || ' requested a change to "' || draft_row.title || '".', caller, profile_row.full_name,
    p_draft_id::text, draft_row.owner_org_id, 'collaboration_draft');
  insert into public.audit_events (actor_id, actor_name, entity_type, entity_id, action, reason, after_data, org_id)
  values (caller, profile_row.full_name, 'collaboration_change_request', request_row.id::text,
    'collaboration.change_requested', request_row.reason, request_row.proposed_change, draft_row.owner_org_id);
  return request_row;
end;
$$;

-- A participating Head may revise only their own organization's proposed
-- staffing. Structural fields and every other organization's people are
-- compared server-side so bypassing the UI cannot rewrite someone else's work.
create or replace function public.save_collaboration_staffing_revision(
  p_draft_id uuid,
  p_organization_id uuid,
  p_snapshot jsonb,
  p_change_summary text default 'Participating organization staffing updated'
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
  old_task jsonb;
  new_task jsonb;
  old_external uuid[];
  new_external uuid[];
  new_member uuid;
  next_number int;
  caller_name text := '';
begin
  if not public.is_organization_approver(p_organization_id, caller)
     or not exists (
       select 1 from public.proposal_collaboration_orgs participating
       where participating.draft_id = p_draft_id
         and participating.org_id = p_organization_id
         and participating.staffing_enabled
     ) then raise exception 'Only an approver for a staffing-enabled participant may revise this staffing' using errcode = '42501'; end if;
  select * into draft_row from public.proposal_collaboration_drafts where id = p_draft_id and deleted_at is null for update;
  if not found or draft_row.status = 'committed' then raise exception 'Draft is not editable' using errcode = '22023'; end if;
  select * into current_row from public.proposal_collaboration_revisions where id = draft_row.current_revision_id;
  if jsonb_typeof(p_snapshot -> 'tasks') <> 'array'
     or jsonb_array_length(p_snapshot -> 'tasks') <> jsonb_array_length(current_row.snapshot -> 'tasks') then
    raise exception 'Participating organizations cannot change proposal structure' using errcode = '42501';
  end if;

  for new_task in select value from jsonb_array_elements(p_snapshot -> 'tasks') loop
    select value into old_task from jsonb_array_elements(current_row.snapshot -> 'tasks') where value ->> 'key' = new_task ->> 'key';
    if old_task is null
       or (old_task - 'assignedMemberIds' - 'leadMemberId' - 'reasoning')
          <> (new_task - 'assignedMemberIds' - 'leadMemberId' - 'reasoning') then
      raise exception 'Participating organizations may change only their own staffing' using errcode = '42501';
    end if;
    old_external := array(
      select member_id from jsonb_array_elements_text(coalesce(old_task -> 'assignedMemberIds', '[]'::jsonb)) raw(member_text)
      cross join lateral (select raw.member_text::uuid member_id) member
      join public.profiles profile on profile.id = member.member_id
      where profile.org_id <> p_organization_id
      order by member_id
    );
    new_external := array(
      select member_id from jsonb_array_elements_text(coalesce(new_task -> 'assignedMemberIds', '[]'::jsonb)) raw(member_text)
      cross join lateral (select raw.member_text::uuid member_id) member
      join public.profiles profile on profile.id = member.member_id
      where profile.org_id <> p_organization_id
      order by member_id
    );
    if old_external is distinct from new_external then
      raise exception 'You cannot change another organization''s proposed employees' using errcode = '42501';
    end if;
    for new_member in select value::uuid from jsonb_array_elements_text(coalesce(new_task -> 'assignedMemberIds', '[]'::jsonb)) loop
      if not exists (select 1 from public.profiles where id = new_member and is_active) then raise exception 'Proposed employees must be active' using errcode = '22023'; end if;
    end loop;
    if nullif(new_task ->> 'leadMemberId', '') is not null
       and not (array(select value::uuid from jsonb_array_elements_text(coalesce(new_task -> 'assignedMemberIds', '[]'::jsonb))) @> array[(new_task ->> 'leadMemberId')::uuid]) then
      raise exception 'Task Leader must remain in the proposed team' using errcode = '22023';
    end if;
    if old_task ->> 'leadMemberId' is distinct from new_task ->> 'leadMemberId'
       and not exists (select 1 from public.profiles where id = (new_task ->> 'leadMemberId')::uuid and org_id = p_organization_id and is_active) then
      raise exception 'You may choose a new Task Leader only from your organization' using errcode = '42501';
    end if;
  end loop;
  if current_row.snapshot = p_snapshot then return current_row; end if;
  select coalesce(max(revision_number), 0) + 1 into next_number from public.proposal_collaboration_revisions where draft_id = p_draft_id;
  insert into public.proposal_collaboration_revisions (draft_id, revision_number, snapshot, created_by, change_summary)
  values (p_draft_id, next_number, p_snapshot, caller, coalesce(nullif(btrim(p_change_summary), ''), 'Staffing updated'))
  returning * into revision_row;
  update public.proposal_collaboration_drafts
  set working_snapshot = p_snapshot, current_revision_id = revision_row.id,
      status = case when status in ('in_review', 'ready_to_commit') then 'changes_requested' else status end
  where id = p_draft_id;
  select coalesce(full_name, 'Approver') into caller_name from public.profiles where id = caller;
  insert into public.audit_events (actor_id, actor_name, entity_type, entity_id, action, reason, after_data, org_id)
  values (caller, caller_name, 'collaboration_revision', revision_row.id::text, 'collaboration.staff_replaced', revision_row.change_summary,
    jsonb_build_object('draftId', p_draft_id, 'revision', next_number, 'organizationId', p_organization_id), draft_row.owner_org_id);
  insert into public.audit_events (actor_id, actor_name, entity_type, entity_id, action, reason, after_data, org_id)
  values (caller, caller_name, 'collaboration_revision', revision_row.id::text, 'collaboration.ai_assignment_changed', revision_row.change_summary,
    jsonb_build_object('draftId', p_draft_id, 'revision', next_number, 'organizationId', p_organization_id), draft_row.owner_org_id);
  insert into public.notifications (user_id, type, title, message, actor_id, actor_name, proposal_id, org_id, entity_type)
  values (draft_row.owner_user_id, 'collaboration_revision', 'Collaboration staffing updated',
    caller_name || ' updated proposed staffing for "' || draft_row.title || '". Approvals must be renewed.',
    caller, caller_name, p_draft_id::text, draft_row.owner_org_id, 'collaboration_draft');
  return revision_row;
end;
$$;

create or replace function public.resolve_collaboration_change_request(
  p_request_id uuid,
  p_status text,
  p_reason text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  caller uuid := auth.uid();
  request_row public.proposal_collaboration_change_requests;
  draft_row public.proposal_collaboration_drafts;
  caller_name text := '';
begin
  select * into request_row from public.proposal_collaboration_change_requests where id = p_request_id for update;
  if not found then raise exception 'Change request not found' using errcode = 'P0002'; end if;
  select * into draft_row from public.proposal_collaboration_drafts where id = request_row.draft_id;
  if p_status not in ('accepted', 'rejected', 'withdrawn') then raise exception 'Invalid resolution' using errcode = '22023'; end if;
  if p_status = 'withdrawn' then
    if request_row.requested_by <> caller then raise exception 'Only the requester may withdraw this change' using errcode = '42501'; end if;
  elsif not public.can_manage_collaboration_draft(request_row.draft_id, caller) then
    raise exception 'Only the owning organization may resolve this change' using errcode = '42501';
  end if;
  update public.proposal_collaboration_change_requests
  set status = p_status, resolved_by = caller, resolved_at = now()
  where id = p_request_id and status = 'open';
  select coalesce(full_name, 'User') into caller_name from public.profiles where id = caller;
  insert into public.audit_events (actor_id, actor_name, entity_type, entity_id, action, reason, org_id)
  values (caller, caller_name, 'collaboration_change_request', p_request_id::text,
    'collaboration.change_' || p_status, nullif(btrim(p_reason), ''), draft_row.owner_org_id);
  perform public.refresh_collaboration_readiness(request_row.draft_id);
end;
$$;

create or replace function public.decide_collaboration_review(
  p_draft_id uuid,
  p_organization_id uuid,
  p_decision text,
  p_reason text default null
)
returns public.proposal_collaboration_approvals
language plpgsql
security definer
set search_path = public
as $$
declare
  caller uuid := auth.uid();
  draft_row public.proposal_collaboration_drafts;
  approval_row public.proposal_collaboration_approvals;
  caller_name text := '';
begin
  if p_decision not in ('approved', 'changes_requested', 'declined') then raise exception 'Invalid review decision' using errcode = '22023'; end if;
  if p_decision <> 'approved' and nullif(btrim(p_reason), '') is null then raise exception 'A reason is required' using errcode = '22023'; end if;
  if not public.is_organization_approver(p_organization_id, caller) then raise exception 'Only an authorized organization approver may decide' using errcode = '42501'; end if;
  if not exists (select 1 from public.proposal_collaboration_orgs where draft_id = p_draft_id and org_id = p_organization_id) then raise exception 'Organization is not part of this proposal' using errcode = '42501'; end if;
  select * into draft_row from public.proposal_collaboration_drafts where id = p_draft_id for update;
  if draft_row.status not in ('in_review', 'changes_requested', 'ready_to_commit') then raise exception 'Draft is not in review' using errcode = '22023'; end if;

  insert into public.proposal_collaboration_approvals (
    draft_id, revision_id, organization_id, decision, approved_by, reason
  ) values (
    p_draft_id, draft_row.current_revision_id, p_organization_id, p_decision, caller, nullif(btrim(p_reason), '')
  ) returning * into approval_row;
  select coalesce(full_name, 'Approver') into caller_name from public.profiles where id = caller;

  if p_decision <> 'approved' then
    update public.proposal_collaboration_drafts set status = 'changes_requested' where id = p_draft_id;
  end if;
  insert into public.notifications (user_id, type, title, message, actor_id, actor_name, proposal_id, org_id, entity_type)
  values (draft_row.owner_user_id,
    case when p_decision = 'approved' then 'collaboration_approved' when p_decision = 'declined' then 'collaboration_declined' else 'collaboration_change' end,
    case when p_decision = 'approved' then 'Organization approved proposal' when p_decision = 'declined' then 'Organization declined proposal' else 'Organization requested changes' end,
    caller_name || ' marked "' || draft_row.title || '" as ' || replace(p_decision, '_', ' ') || '.',
    caller, caller_name, p_draft_id::text, draft_row.owner_org_id, 'collaboration_draft');
  insert into public.audit_events (actor_id, actor_name, entity_type, entity_id, action, reason, after_data, org_id)
  values (caller, caller_name, 'collaboration_approval', approval_row.id::text,
    case when p_decision = 'declined' then 'collaboration.declined' else 'collaboration.' || p_decision end,
    approval_row.reason, jsonb_build_object('draftId', p_draft_id, 'revisionId', draft_row.current_revision_id, 'organizationId', p_organization_id), draft_row.owner_org_id);
  perform public.refresh_collaboration_readiness(p_draft_id);
  return approval_row;
end;
$$;

-- Private source PDF storage. Files use {draft-id}/source.pdf.
insert into storage.buckets (id, name, public)
values ('proposal-drafts', 'proposal-drafts', false)
on conflict (id) do update set public = false;

create or replace function public.collaboration_storage_draft_id(object_name text)
returns uuid
language plpgsql
immutable
as $$
begin
  return split_part(object_name, '/', 1)::uuid;
exception when others then return null;
end;
$$;

drop policy if exists collaboration_source_read on storage.objects;
create policy collaboration_source_read on storage.objects
for select to authenticated using (
  bucket_id = 'proposal-drafts'
  and public.is_collaboration_participant(public.collaboration_storage_draft_id(name), auth.uid())
);
drop policy if exists collaboration_source_insert on storage.objects;
create policy collaboration_source_insert on storage.objects
for insert to authenticated with check (
  bucket_id = 'proposal-drafts'
  and public.can_manage_collaboration_draft(public.collaboration_storage_draft_id(name), auth.uid())
);
drop policy if exists collaboration_source_update on storage.objects;
create policy collaboration_source_update on storage.objects
for update to authenticated using (
  bucket_id = 'proposal-drafts'
  and public.can_manage_collaboration_draft(public.collaboration_storage_draft_id(name), auth.uid())
);

alter table public.proposal_collaboration_messages enable row level security;
alter table public.proposal_collaboration_change_requests enable row level security;
alter table public.proposal_collaboration_approvals enable row level security;
create policy collaboration_messages_read on public.proposal_collaboration_messages for select to authenticated using (public.is_collaboration_participant(draft_id, auth.uid()));
create policy collaboration_changes_read on public.proposal_collaboration_change_requests for select to authenticated using (public.is_collaboration_participant(draft_id, auth.uid()));
create policy collaboration_approvals_read on public.proposal_collaboration_approvals for select to authenticated using (public.is_collaboration_participant(draft_id, auth.uid()));

revoke all on function public.organization_approver_ids(uuid) from public, anon;
revoke all on function public.collaboration_readiness(uuid) from public, anon;
revoke all on function public.refresh_collaboration_readiness(uuid) from public, anon;
revoke all on function public.request_collaboration_review(uuid) from public, anon;
revoke all on function public.send_collaboration_message(uuid, text, text, text, text) from public, anon;
revoke all on function public.create_collaboration_change_request(uuid, text, text, text, jsonb, uuid) from public, anon;
revoke all on function public.save_collaboration_staffing_revision(uuid, uuid, jsonb, text) from public, anon;
revoke all on function public.resolve_collaboration_change_request(uuid, text, text) from public, anon;
revoke all on function public.decide_collaboration_review(uuid, uuid, text, text) from public, anon;
grant execute on function public.organization_approver_ids(uuid) to authenticated;
grant execute on function public.collaboration_readiness(uuid) to authenticated;
grant execute on function public.request_collaboration_review(uuid) to authenticated;
grant execute on function public.send_collaboration_message(uuid, text, text, text, text) to authenticated;
grant execute on function public.create_collaboration_change_request(uuid, text, text, text, jsonb, uuid) to authenticated;
grant execute on function public.save_collaboration_staffing_revision(uuid, uuid, jsonb, text) to authenticated;
grant execute on function public.resolve_collaboration_change_request(uuid, text, text) to authenticated;
grant execute on function public.decide_collaboration_review(uuid, uuid, text, text) to authenticated;
grant select on public.proposal_collaboration_messages to authenticated;
grant select on public.proposal_collaboration_change_requests to authenticated;
grant select on public.proposal_collaboration_approvals to authenticated;

notify pgrst, 'reload schema';
