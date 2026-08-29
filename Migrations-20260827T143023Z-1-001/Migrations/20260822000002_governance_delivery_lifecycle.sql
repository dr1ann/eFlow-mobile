-- Proposal governance, named decision makers, closeout, and atomic delivery
-- completion/archive. This migration is additive and keeps the existing
-- organization approval rows as the proposal-level compatibility contract.

begin;

alter table public.proposal_collaboration_orgs
  drop constraint if exists proposal_collaboration_orgs_participation_role_check;
alter table public.proposal_collaboration_orgs
  add constraint proposal_collaboration_orgs_participation_role_check
  check (participation_role in ('owner', 'participant', 'governance', 'consulted', 'observer'));
alter table public.proposal_collaboration_orgs
  add column if not exists approval_policy text not null default 'one_of',
  add column if not exists quorum_count int not null default 1,
  add column if not exists approval_sequence int not null default 1,
  add column if not exists review_deadline_days int not null default 5;
alter table public.proposal_collaboration_orgs
  drop constraint if exists proposal_collaboration_orgs_approval_policy_check;
alter table public.proposal_collaboration_orgs
  add constraint proposal_collaboration_orgs_approval_policy_check
  check (approval_policy in ('one_of', 'all', 'quorum'));
alter table public.proposal_collaboration_orgs
  drop constraint if exists proposal_collaboration_orgs_quorum_count_check;
alter table public.proposal_collaboration_orgs
  add constraint proposal_collaboration_orgs_quorum_count_check check (quorum_count > 0);
alter table public.proposal_collaboration_orgs
  drop constraint if exists proposal_collaboration_orgs_review_deadline_days_check;
alter table public.proposal_collaboration_orgs
  add constraint proposal_collaboration_orgs_review_deadline_days_check
  check (review_deadline_days between 1 and 90);

alter table public.project_organizations
  drop constraint if exists project_organizations_participation_role_check;
alter table public.project_organizations
  add constraint project_organizations_participation_role_check
  check (participation_role in ('owner', 'participant', 'governance', 'consulted', 'observer'));

alter table public.tasks
  add column if not exists governance_organization_id uuid references public.organizations(id) on delete set null,
  add column if not exists governance_approval_mode text not null default 'department';
alter table public.tasks drop constraint if exists tasks_governance_approval_mode_check;
alter table public.tasks add constraint tasks_governance_approval_mode_check
  check (governance_approval_mode in ('department', 'governance', 'closeout_only'));
create index if not exists tasks_governance_organization_idx
  on public.tasks(governance_organization_id) where governance_organization_id is not null;

create table if not exists public.proposal_governance_assignments (
  id uuid primary key default gen_random_uuid(),
  draft_id uuid not null references public.proposal_collaboration_drafts(id) on delete cascade,
  organization_id uuid not null references public.organizations(id) on delete restrict,
  user_id uuid not null references public.profiles(id) on delete restrict,
  assignment_role text not null check (assignment_role in (
    'primary_approver', 'backup_approver', 'liaison',
    'technical_reviewer', 'observer', 'delegate'
  )),
  assigned_by uuid not null references public.profiles(id) on delete restrict,
  delegated_by uuid references public.profiles(id) on delete set null,
  valid_until timestamptz,
  created_at timestamptz not null default now(),
  unique (draft_id, organization_id, user_id, assignment_role)
);
create index if not exists proposal_governance_assignments_draft_idx
  on public.proposal_governance_assignments(draft_id, organization_id, assignment_role);

create table if not exists public.proposal_governance_signoffs (
  id uuid primary key default gen_random_uuid(),
  draft_id uuid not null references public.proposal_collaboration_drafts(id) on delete cascade,
  revision_id uuid not null references public.proposal_collaboration_revisions(id) on delete cascade,
  organization_id uuid not null references public.organizations(id) on delete restrict,
  user_id uuid not null references public.profiles(id) on delete restrict,
  decision text not null check (decision in ('approved', 'changes_requested', 'declined', 'recused')),
  reason text,
  delegated_to uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  unique (revision_id, organization_id, user_id)
);
create index if not exists proposal_governance_signoffs_draft_idx
  on public.proposal_governance_signoffs(draft_id, revision_id, organization_id, created_at desc);

create table if not exists public.proposal_governance_records (
  id uuid primary key default gen_random_uuid(),
  draft_id uuid not null references public.proposal_collaboration_drafts(id) on delete cascade,
  organization_id uuid not null references public.organizations(id) on delete restrict,
  resolution_number text,
  meeting_date date,
  minutes_file_name text,
  minutes_file_path text,
  endorsement text,
  recorded_by uuid not null references public.profiles(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (draft_id, organization_id)
);
drop trigger if exists proposal_governance_records_touch on public.proposal_governance_records;
create trigger proposal_governance_records_touch before update on public.proposal_governance_records
for each row execute function public.touch_updated_at();

create table if not exists public.proposal_delivery_closeouts (
  draft_id uuid primary key references public.proposal_collaboration_drafts(id) on delete cascade,
  status text not null default 'draft' check (status in (
    'draft', 'pending', 'changes_requested', 'approved', 'completed', 'archived'
  )),
  request_note text,
  requested_by uuid references public.profiles(id) on delete set null,
  requested_at timestamptz,
  approved_at timestamptz,
  completed_by uuid references public.profiles(id) on delete set null,
  completed_at timestamptz,
  archived_by uuid references public.profiles(id) on delete set null,
  archived_at timestamptz,
  updated_at timestamptz not null default now()
);
drop trigger if exists proposal_delivery_closeouts_touch on public.proposal_delivery_closeouts;
create trigger proposal_delivery_closeouts_touch before update on public.proposal_delivery_closeouts
for each row execute function public.touch_updated_at();

create table if not exists public.proposal_delivery_closeout_decisions (
  id uuid primary key default gen_random_uuid(),
  draft_id uuid not null references public.proposal_delivery_closeouts(draft_id) on delete cascade,
  organization_id uuid not null references public.organizations(id) on delete restrict,
  decision text not null check (decision in ('approved', 'changes_requested', 'declined')),
  decided_by uuid not null references public.profiles(id) on delete restrict,
  reason text,
  resolution_number text,
  meeting_date date,
  created_at timestamptz not null default now(),
  unique (draft_id, organization_id)
);

create or replace function public.can_manage_proposal_delivery(target_draft uuid, caller_id uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
  select caller_id is not null and exists (
    select 1 from public.proposal_collaboration_drafts draft
    where draft.id = target_draft
      and draft.deleted_at is null
      and public.auth_role(caller_id) <> 'super_admin'
      and (
        draft.owner_user_id = caller_id
        or public.is_organization_approver(draft.owner_org_id, caller_id)
      )
  );
$$;

create or replace function public.is_proposal_governance_decider(
  target_draft uuid,
  target_org uuid,
  caller_id uuid
)
returns boolean
language sql stable security definer set search_path = public
as $$
  select caller_id is not null and (
    public.is_organization_approver(target_org, caller_id)
    or exists (
      select 1 from public.proposal_governance_assignments assignment
      where assignment.draft_id = target_draft
        and assignment.organization_id = target_org
        and assignment.user_id = caller_id
        and assignment.assignment_role in ('primary_approver', 'backup_approver', 'delegate')
        and (assignment.valid_until is null or assignment.valid_until > now())
    )
  );
$$;

create or replace function public.set_proposal_governance_configuration(
  p_draft_id uuid,
  p_organizations jsonb,
  p_assignments jsonb
)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  caller uuid := auth.uid();
  draft_row public.proposal_collaboration_drafts;
  item jsonb;
  target_org uuid;
  target_user uuid;
  target_role text;
begin
  if not public.can_manage_collaboration_draft(p_draft_id, caller) then
    raise exception 'Only the owning organization may configure proposal governance' using errcode = '42501';
  end if;
  select * into draft_row from public.proposal_collaboration_drafts where id = p_draft_id for update;
  if draft_row.status in ('committed', 'archived', 'deleted') then
    raise exception 'Governance configuration is locked after publication' using errcode = '22023';
  end if;
  if jsonb_typeof(coalesce(p_organizations, '[]'::jsonb)) <> 'array'
     or jsonb_typeof(coalesce(p_assignments, '[]'::jsonb)) <> 'array' then
    raise exception 'Governance configuration must be arrays' using errcode = '22023';
  end if;

  for item in select value from jsonb_array_elements(p_organizations) loop
    target_org := nullif(item ->> 'orgId', '')::uuid;
    if target_org is null or not exists (
      select 1 from public.proposal_collaboration_orgs participant
      where participant.draft_id = p_draft_id and participant.org_id = target_org
    ) then raise exception 'Governance organization is not part of this proposal' using errcode = '22023'; end if;
    update public.proposal_collaboration_orgs set
      approval_policy = case when item ->> 'approvalPolicy' in ('one_of', 'all', 'quorum') then item ->> 'approvalPolicy' else 'one_of' end,
      quorum_count = greatest(1, coalesce(nullif(item ->> 'quorumCount', '')::int, 1)),
      approval_sequence = greatest(1, coalesce(nullif(item ->> 'sequence', '')::int, 1)),
      review_deadline_days = greatest(1, least(90, coalesce(nullif(item ->> 'reviewDeadlineDays', '')::int, 5)))
    where draft_id = p_draft_id and org_id = target_org;
  end loop;

  delete from public.proposal_governance_assignments where draft_id = p_draft_id;
  for item in select value from jsonb_array_elements(p_assignments) loop
    target_org := nullif(item ->> 'organizationId', '')::uuid;
    target_user := nullif(item ->> 'userId', '')::uuid;
    target_role := item ->> 'role';
    if target_role not in ('primary_approver', 'backup_approver', 'liaison', 'technical_reviewer', 'observer') then
      raise exception 'Invalid governance assignment role' using errcode = '22023';
    end if;
    if not exists (
      select 1 from public.proposal_collaboration_orgs participant
      where participant.draft_id = p_draft_id and participant.org_id = target_org
    ) or not exists (
      select 1 from public.profiles profile
      where profile.id = target_user and profile.is_active
        and (profile.org_id = target_org or public.is_organization_member(target_org, profile.id))
    ) then raise exception 'Governance assignee must be an active member of the selected organization' using errcode = '22023'; end if;
    insert into public.proposal_governance_assignments (
      draft_id, organization_id, user_id, assignment_role, assigned_by
    ) values (p_draft_id, target_org, target_user, target_role, caller);
  end loop;

  insert into public.audit_events (actor_id, actor_name, entity_type, entity_id, action, after_data, org_id)
  values (caller, coalesce((select full_name from public.profiles where id = caller), 'Owner'),
    'collaboration_draft', p_draft_id::text, 'governance.configuration_updated',
    jsonb_build_object('organizationCount', jsonb_array_length(p_organizations), 'assignmentCount', jsonb_array_length(p_assignments)),
    draft_row.owner_org_id);
end;
$$;

create or replace function public.recuse_and_delegate_collaboration_review(
  p_draft_id uuid,
  p_organization_id uuid,
  p_reason text,
  p_delegate_to uuid default null,
  p_valid_until timestamptz default null
)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  caller uuid := auth.uid();
  draft_row public.proposal_collaboration_drafts;
begin
  if nullif(btrim(p_reason), '') is null then raise exception 'A recusal reason is required' using errcode = '22023'; end if;
  if not public.is_proposal_governance_decider(p_draft_id, p_organization_id, caller) then
    raise exception 'Only the current decision maker may recuse' using errcode = '42501';
  end if;
  select * into draft_row from public.proposal_collaboration_drafts where id = p_draft_id for update;
  if draft_row.status not in ('in_review', 'changes_requested', 'ready_to_commit') then
    raise exception 'Proposal is not in review' using errcode = '22023';
  end if;
  if p_delegate_to = caller then raise exception 'You cannot delegate to yourself' using errcode = '22023'; end if;
  if p_delegate_to is not null and not exists (
    select 1 from public.profiles profile where profile.id = p_delegate_to and profile.is_active
      and (profile.org_id = p_organization_id or public.is_organization_member(p_organization_id, profile.id))
  ) then raise exception 'Delegate must be an active member of the organization' using errcode = '22023'; end if;

  insert into public.proposal_governance_signoffs (
    draft_id, revision_id, organization_id, user_id, decision, reason, delegated_to
  ) values (p_draft_id, draft_row.current_revision_id, p_organization_id, caller, 'recused', btrim(p_reason), p_delegate_to)
  on conflict (revision_id, organization_id, user_id) do update
    set decision = 'recused', reason = excluded.reason, delegated_to = excluded.delegated_to, created_at = now();
  if p_delegate_to is not null then
    insert into public.proposal_governance_assignments (
      draft_id, organization_id, user_id, assignment_role, assigned_by, delegated_by, valid_until
    ) values (p_draft_id, p_organization_id, p_delegate_to, 'delegate', caller, caller, p_valid_until)
    on conflict (draft_id, organization_id, user_id, assignment_role) do update
      set delegated_by = caller, valid_until = excluded.valid_until, assigned_by = caller, created_at = now();
    insert into public.notifications (user_id, type, title, message, actor_id, actor_name, proposal_id, org_id, entity_type)
    values (p_delegate_to, 'collaboration_request', 'Governance review delegated',
      coalesce((select full_name from public.profiles where id = caller), 'An approver') || ' delegated review of "' || draft_row.title || '" to you.',
      caller, coalesce((select full_name from public.profiles where id = caller), 'Approver'), p_draft_id::text, p_organization_id, 'collaboration_draft');
  end if;
  insert into public.audit_events (actor_id, actor_name, entity_type, entity_id, action, reason, after_data, org_id)
  values (caller, coalesce((select full_name from public.profiles where id = caller), 'Approver'),
    'collaboration_approval', draft_row.current_revision_id::text, 'governance.approver_recused', btrim(p_reason),
    jsonb_build_object('draftId', p_draft_id, 'organizationId', p_organization_id, 'delegatedTo', p_delegate_to), p_organization_id);
end;
$$;

create or replace function public.save_proposal_governance_record(
  p_draft_id uuid,
  p_organization_id uuid,
  p_resolution_number text,
  p_meeting_date date,
  p_minutes_file_name text,
  p_minutes_file_path text,
  p_endorsement text
)
returns public.proposal_governance_records
language plpgsql security definer set search_path = public
as $$
declare
  caller uuid := auth.uid();
  result public.proposal_governance_records;
begin
  if not public.is_proposal_governance_decider(p_draft_id, p_organization_id, caller) then
    raise exception 'Only an assigned governance decision maker may record the Board action' using errcode = '42501';
  end if;
  insert into public.proposal_governance_records (
    draft_id, organization_id, resolution_number, meeting_date,
    minutes_file_name, minutes_file_path, endorsement, recorded_by
  ) values (
    p_draft_id, p_organization_id, nullif(btrim(p_resolution_number), ''), p_meeting_date,
    nullif(btrim(p_minutes_file_name), ''), nullif(btrim(p_minutes_file_path), ''),
    nullif(btrim(p_endorsement), ''), caller
  ) on conflict (draft_id, organization_id) do update set
    resolution_number = excluded.resolution_number,
    meeting_date = excluded.meeting_date,
    minutes_file_name = excluded.minutes_file_name,
    minutes_file_path = excluded.minutes_file_path,
    endorsement = excluded.endorsement,
    recorded_by = caller
  returning * into result;
  return result;
end;
$$;

create or replace function public.request_proposal_closeout(p_draft_id uuid, p_note text default null)
returns public.proposal_delivery_closeouts
language plpgsql security definer set search_path = public
as $$
declare
  caller uuid := auth.uid();
  draft_row public.proposal_collaboration_drafts;
  result public.proposal_delivery_closeouts;
  governance_count int;
begin
  if not public.can_manage_proposal_delivery(p_draft_id, caller) then
    raise exception 'Only the owning organization may request proposal closeout' using errcode = '42501';
  end if;
  select * into draft_row from public.proposal_collaboration_drafts where id = p_draft_id for update;
  if draft_row.status <> 'committed' then raise exception 'Only a published proposal can enter closeout' using errcode = '22023'; end if;
  if exists (
    select 1 from public.tasks task
    where task.source_collaboration_draft_id = p_draft_id
      and task.deleted_at is null and task.archived_at is null
      and task.status not in ('completed', 'cancelled')
  ) then raise exception 'Every active task must be approved or cancelled before closeout' using errcode = '22023'; end if;
  select count(*) into governance_count from public.proposal_collaboration_orgs
  where draft_id = p_draft_id and participation_role = 'governance';
  delete from public.proposal_delivery_closeout_decisions where draft_id = p_draft_id;
  insert into public.proposal_delivery_closeouts (
    draft_id, status, request_note, requested_by, requested_at, approved_at
  ) values (
    p_draft_id, case when governance_count = 0 then 'approved' else 'pending' end,
    nullif(btrim(p_note), ''), caller, now(), case when governance_count = 0 then now() end
  ) on conflict (draft_id) do update set
    status = excluded.status, request_note = excluded.request_note,
    requested_by = caller, requested_at = now(), approved_at = excluded.approved_at,
    completed_by = null, completed_at = null, archived_by = null, archived_at = null
  returning * into result;
  insert into public.notifications (user_id, type, title, message, actor_id, actor_name, proposal_id, org_id, entity_type)
  select distinct approver_id, 'collaboration_request', 'Proposal closeout requires review',
    'Final delivery for "' || draft_row.title || '" is ready for governance closeout.',
    caller, coalesce((select full_name from public.profiles where id = caller), 'Owner'), p_draft_id::text, participant.org_id, 'proposal_closeout'
  from public.proposal_collaboration_orgs participant
  cross join lateral (
    select assignment.user_id as approver_id
    from public.proposal_governance_assignments assignment
    where assignment.draft_id = p_draft_id and assignment.organization_id = participant.org_id
      and assignment.assignment_role in ('primary_approver', 'backup_approver', 'delegate')
      and (assignment.valid_until is null or assignment.valid_until > now())
      and not exists (
        select 1
        from public.proposal_governance_signoffs signoff
        where signoff.revision_id = draft_row.current_revision_id
          and signoff.organization_id = participant.org_id
          and signoff.user_id = assignment.user_id
          and signoff.decision = 'recused'
      )
    union
    select fallback_id
    from public.organization_approver_ids(participant.org_id) fallback_id
    where not exists (
      select 1 from public.proposal_governance_assignments assignment
      where assignment.draft_id = p_draft_id and assignment.organization_id = participant.org_id
        and assignment.assignment_role in ('primary_approver', 'backup_approver', 'delegate')
        and (assignment.valid_until is null or assignment.valid_until > now())
    )
      and not exists (
        select 1
        from public.proposal_governance_signoffs signoff
        where signoff.revision_id = draft_row.current_revision_id
          and signoff.organization_id = participant.org_id
          and signoff.user_id = fallback_id
          and signoff.decision = 'recused'
      )
  ) reviewer
  where participant.draft_id = p_draft_id and participant.participation_role = 'governance'
    and reviewer.approver_id <> caller;
  insert into public.audit_events (actor_id, actor_name, entity_type, entity_id, action, reason, after_data, org_id)
  values (caller, coalesce((select full_name from public.profiles where id = caller), 'Owner'),
    'proposal_closeout', p_draft_id::text, 'proposal.closeout_requested', nullif(btrim(p_note), ''),
    jsonb_build_object('governanceOrganizations', governance_count), draft_row.owner_org_id);
  return result;
end;
$$;

create or replace function public.decide_proposal_closeout(
  p_draft_id uuid,
  p_organization_id uuid,
  p_decision text,
  p_reason text default null,
  p_resolution_number text default null,
  p_meeting_date date default null
)
returns public.proposal_delivery_closeout_decisions
language plpgsql security definer set search_path = public
as $$
declare
  caller uuid := auth.uid();
  draft_row public.proposal_collaboration_drafts;
  result public.proposal_delivery_closeout_decisions;
begin
  if p_decision not in ('approved', 'changes_requested', 'declined') then raise exception 'Invalid closeout decision' using errcode = '22023'; end if;
  if p_decision <> 'approved' and nullif(btrim(p_reason), '') is null then raise exception 'A reason is required' using errcode = '22023'; end if;
  if not exists (select 1 from public.proposal_collaboration_orgs where draft_id = p_draft_id and org_id = p_organization_id and participation_role = 'governance') then
    raise exception 'This organization is not a governance reviewer for the proposal' using errcode = '42501';
  end if;
  if not public.is_proposal_governance_decider(p_draft_id, p_organization_id, caller) then
    raise exception 'Only an assigned governance decision maker may decide closeout' using errcode = '42501';
  end if;
  select * into draft_row from public.proposal_collaboration_drafts where id = p_draft_id;
  if not exists (select 1 from public.proposal_delivery_closeouts where draft_id = p_draft_id and status in ('pending', 'changes_requested')) then
    raise exception 'Closeout is not awaiting a decision' using errcode = '22023';
  end if;
  insert into public.proposal_delivery_closeout_decisions (
    draft_id, organization_id, decision, decided_by, reason, resolution_number, meeting_date
  ) values (
    p_draft_id, p_organization_id, p_decision, caller, nullif(btrim(p_reason), ''),
    nullif(btrim(p_resolution_number), ''), p_meeting_date
  ) on conflict (draft_id, organization_id) do update set
    decision = excluded.decision, decided_by = caller, reason = excluded.reason,
    resolution_number = excluded.resolution_number, meeting_date = excluded.meeting_date, created_at = now()
  returning * into result;
  if p_decision <> 'approved' then
    update public.proposal_delivery_closeouts set status = 'changes_requested', approved_at = null where draft_id = p_draft_id;
  elsif not exists (
    select 1 from public.proposal_collaboration_orgs participant
    where participant.draft_id = p_draft_id and participant.participation_role = 'governance'
      and not exists (
        select 1 from public.proposal_delivery_closeout_decisions decision
        where decision.draft_id = p_draft_id and decision.organization_id = participant.org_id and decision.decision = 'approved'
      )
  ) then
    update public.proposal_delivery_closeouts set status = 'approved', approved_at = now() where draft_id = p_draft_id;
  end if;
  insert into public.notifications (user_id, type, title, message, actor_id, actor_name, proposal_id, org_id, entity_type)
  values (draft_row.owner_user_id, case when p_decision = 'approved' then 'collaboration_approved' else 'collaboration_change' end,
    case when p_decision = 'approved' then 'Governance approved proposal closeout' else 'Governance returned proposal closeout' end,
    coalesce((select full_name from public.profiles where id = caller), 'Governance reviewer') || ' marked closeout of "' || draft_row.title || '" as ' || replace(p_decision, '_', ' ') || '.',
    caller, coalesce((select full_name from public.profiles where id = caller), 'Reviewer'), p_draft_id::text, draft_row.owner_org_id, 'proposal_closeout');
  return result;
end;
$$;

create or replace function public.complete_proposal_delivery(p_draft_id uuid, p_note text default null)
returns jsonb
language plpgsql security definer set search_path = public
as $$
declare
  caller uuid := auth.uid();
  draft_row public.proposal_collaboration_drafts;
  changed_projects int;
begin
  if not public.can_manage_proposal_delivery(p_draft_id, caller) then
    raise exception 'Only the owning organization may complete proposal delivery' using errcode = '42501';
  end if;
  select * into draft_row from public.proposal_collaboration_drafts where id = p_draft_id for update;
  if draft_row.status <> 'committed' then raise exception 'Proposal is not in active delivery' using errcode = '22023'; end if;
  if exists (
    select 1 from public.tasks task where task.source_collaboration_draft_id = p_draft_id
      and task.deleted_at is null and task.archived_at is null and task.status not in ('completed', 'cancelled')
  ) then raise exception 'Every task must be approved or cancelled before completing the proposal' using errcode = '22023'; end if;
  if exists (select 1 from public.proposal_collaboration_orgs where draft_id = p_draft_id and participation_role = 'governance')
     and not exists (select 1 from public.proposal_delivery_closeouts where draft_id = p_draft_id and status = 'approved') then
    raise exception 'Final governance closeout approval is required' using errcode = '22023';
  end if;
  update public.projects set status = 'completed', updated_at = now()
  where source_collaboration_draft_id = p_draft_id and status <> 'archived';
  get diagnostics changed_projects = row_count;
  insert into public.proposal_delivery_closeouts (draft_id, status, completed_by, completed_at)
  values (p_draft_id, 'completed', caller, now())
  on conflict (draft_id) do update set status = 'completed', completed_by = caller, completed_at = now();
  insert into public.audit_events (actor_id, actor_name, entity_type, entity_id, action, reason, after_data, org_id)
  values (caller, coalesce((select full_name from public.profiles where id = caller), 'Owner'),
    'collaboration_draft', p_draft_id::text, 'proposal.delivery_completed', nullif(btrim(p_note), ''),
    jsonb_build_object('projectCount', changed_projects), draft_row.owner_org_id);
  return jsonb_build_object('draftId', p_draft_id, 'projectCount', changed_projects, 'status', 'completed');
end;
$$;

create or replace function public.archive_proposal_delivery(p_draft_id uuid, p_reason text)
returns jsonb
language plpgsql security definer set search_path = public
as $$
declare
  caller uuid := auth.uid();
  draft_row public.proposal_collaboration_drafts;
  changed_projects int;
  changed_tasks int;
begin
  if nullif(btrim(p_reason), '') is null then raise exception 'An archive reason is required' using errcode = '22023'; end if;
  if not public.can_manage_proposal_delivery(p_draft_id, caller) then
    raise exception 'Only the owning organization may archive proposal delivery' using errcode = '42501';
  end if;
  select * into draft_row from public.proposal_collaboration_drafts where id = p_draft_id for update;
  if draft_row.status = 'archived' then
    return jsonb_build_object('draftId', p_draft_id, 'projectCount', 0, 'taskCount', 0, 'status', 'archived');
  end if;
  if not exists (select 1 from public.proposal_delivery_closeouts where draft_id = p_draft_id and status = 'completed')
     and exists (select 1 from public.projects where source_collaboration_draft_id = p_draft_id and status <> 'completed') then
    raise exception 'Complete proposal delivery before archiving it' using errcode = '22023';
  end if;
  update public.tasks set archived_at = now(), last_activity_at = now()
  where source_collaboration_draft_id = p_draft_id and deleted_at is null and archived_at is null;
  get diagnostics changed_tasks = row_count;
  update public.projects set status = 'archived', archived_at = now(), updated_at = now()
  where source_collaboration_draft_id = p_draft_id and status <> 'archived';
  get diagnostics changed_projects = row_count;
  update public.proposal_collaboration_drafts set status = 'archived', archived_at = now()
  where id = p_draft_id;
  insert into public.proposal_delivery_closeouts (draft_id, status, archived_by, archived_at)
  values (p_draft_id, 'archived', caller, now())
  on conflict (draft_id) do update set status = 'archived', archived_by = caller, archived_at = now();
  insert into public.audit_events (actor_id, actor_name, entity_type, entity_id, action, reason, after_data, org_id)
  values (caller, coalesce((select full_name from public.profiles where id = caller), 'Owner'),
    'collaboration_draft', p_draft_id::text, 'proposal.delivery_archived', btrim(p_reason),
    jsonb_build_object('projectCount', changed_projects, 'taskCount', changed_tasks), draft_row.owner_org_id);
  return jsonb_build_object('draftId', p_draft_id, 'projectCount', changed_projects, 'taskCount', changed_tasks, 'status', 'archived');
end;
$$;

create or replace function public.run_governance_review_escalations()
returns int
language plpgsql security definer set search_path = public
as $$
declare
  caller uuid := auth.uid();
  inserted_count int := 0;
begin
  if caller is null then raise exception 'Not authenticated' using errcode = '42501'; end if;
  insert into public.notifications (user_id, type, title, message, actor_id, actor_name, proposal_id, org_id, entity_type)
  select distinct reviewer.approver_id, 'collaboration_request', 'Governance review overdue',
    'Review of "' || draft.title || '" is overdue. Please decide or delegate it.',
    draft.owner_user_id, coalesce(owner.full_name, 'Proposal owner'), draft.id::text, participant.org_id, 'collaboration_draft'
  from public.proposal_collaboration_orgs participant
  join public.proposal_collaboration_drafts draft on draft.id = participant.draft_id
  left join public.profiles owner on owner.id = draft.owner_user_id
  cross join lateral (
    select assignment.user_id as approver_id
    from public.proposal_governance_assignments assignment
    where assignment.draft_id = draft.id and assignment.organization_id = participant.org_id
      and assignment.assignment_role in ('primary_approver', 'backup_approver', 'delegate')
      and (assignment.valid_until is null or assignment.valid_until > now())
      and not exists (
        select 1
        from public.proposal_governance_signoffs signoff
        where signoff.revision_id = draft.current_revision_id
          and signoff.organization_id = participant.org_id
          and signoff.user_id = assignment.user_id
          and signoff.decision = 'recused'
      )
    union
    select fallback_id
    from public.organization_approver_ids(participant.org_id) fallback_id
    where not exists (
      select 1 from public.proposal_governance_assignments assignment
      where assignment.draft_id = draft.id and assignment.organization_id = participant.org_id
        and assignment.assignment_role in ('primary_approver', 'backup_approver', 'delegate')
        and (assignment.valid_until is null or assignment.valid_until > now())
    )
      and not exists (
        select 1
        from public.proposal_governance_signoffs signoff
        where signoff.revision_id = draft.current_revision_id
          and signoff.organization_id = participant.org_id
          and signoff.user_id = fallback_id
          and signoff.decision = 'recused'
      )
  ) reviewer
  where participant.participation_role in ('participant', 'governance')
    and draft.status in ('in_review', 'changes_requested', 'ready_to_commit')
    and participant.requested_at is not null
    and participant.requested_at + make_interval(days => participant.review_deadline_days) < now()
    and not exists (
      select 1 from public.proposal_collaboration_approvals approval
      where approval.revision_id = draft.current_revision_id and approval.organization_id = participant.org_id and approval.decision = 'approved'
    )
    and not exists (
      select 1 from public.notifications notification
      where notification.user_id = reviewer.approver_id and notification.proposal_id = draft.id::text
        and notification.type = 'collaboration_request' and notification.title = 'Governance review overdue'
        and notification.created_at::date = current_date
    );
  get diagnostics inserted_count = row_count;
  return inserted_count;
end;
$$;

alter table public.proposal_governance_assignments enable row level security;
alter table public.proposal_governance_signoffs enable row level security;
alter table public.proposal_governance_records enable row level security;
alter table public.proposal_delivery_closeouts enable row level security;
alter table public.proposal_delivery_closeout_decisions enable row level security;
drop policy if exists proposal_governance_assignments_read on public.proposal_governance_assignments;
create policy proposal_governance_assignments_read on public.proposal_governance_assignments
for select to authenticated using (public.is_collaboration_participant(draft_id, auth.uid()));
drop policy if exists proposal_governance_signoffs_read on public.proposal_governance_signoffs;
create policy proposal_governance_signoffs_read on public.proposal_governance_signoffs
for select to authenticated using (public.is_collaboration_participant(draft_id, auth.uid()));
drop policy if exists proposal_governance_records_read on public.proposal_governance_records;
create policy proposal_governance_records_read on public.proposal_governance_records
for select to authenticated using (public.is_collaboration_participant(draft_id, auth.uid()));
drop policy if exists proposal_delivery_closeouts_read on public.proposal_delivery_closeouts;
create policy proposal_delivery_closeouts_read on public.proposal_delivery_closeouts
for select to authenticated using (public.is_collaboration_participant(draft_id, auth.uid()));
drop policy if exists proposal_delivery_closeout_decisions_read on public.proposal_delivery_closeout_decisions;
create policy proposal_delivery_closeout_decisions_read on public.proposal_delivery_closeout_decisions
for select to authenticated using (public.is_collaboration_participant(draft_id, auth.uid()));

grant select on public.proposal_governance_assignments, public.proposal_governance_signoffs,
  public.proposal_governance_records, public.proposal_delivery_closeouts,
  public.proposal_delivery_closeout_decisions to authenticated;
revoke all on function public.can_manage_proposal_delivery(uuid, uuid) from public, anon;
revoke all on function public.is_proposal_governance_decider(uuid, uuid, uuid) from public, anon;
revoke all on function public.set_proposal_governance_configuration(uuid, jsonb, jsonb) from public, anon;
revoke all on function public.recuse_and_delegate_collaboration_review(uuid, uuid, text, uuid, timestamptz) from public, anon;
revoke all on function public.save_proposal_governance_record(uuid, uuid, text, date, text, text, text) from public, anon;
revoke all on function public.request_proposal_closeout(uuid, text) from public, anon;
revoke all on function public.decide_proposal_closeout(uuid, uuid, text, text, text, date) from public, anon;
revoke all on function public.complete_proposal_delivery(uuid, text) from public, anon;
revoke all on function public.archive_proposal_delivery(uuid, text) from public, anon;
revoke all on function public.run_governance_review_escalations() from public, anon;
grant execute on function public.can_manage_proposal_delivery(uuid, uuid) to authenticated;
grant execute on function public.is_proposal_governance_decider(uuid, uuid, uuid) to authenticated;
grant execute on function public.set_proposal_governance_configuration(uuid, jsonb, jsonb) to authenticated;
grant execute on function public.recuse_and_delegate_collaboration_review(uuid, uuid, text, uuid, timestamptz) to authenticated;
grant execute on function public.save_proposal_governance_record(uuid, uuid, text, date, text, text, text) to authenticated;
grant execute on function public.request_proposal_closeout(uuid, text) to authenticated;
grant execute on function public.decide_proposal_closeout(uuid, uuid, text, text, text, date) to authenticated;
grant execute on function public.complete_proposal_delivery(uuid, text) to authenticated;
grant execute on function public.archive_proposal_delivery(uuid, text) to authenticated;
grant execute on function public.run_governance_review_escalations() to authenticated;

notify pgrst, 'reload schema';
commit;
