-- The organization that authors a proposal does not review its own work.
-- Sending a revision for collaboration review records its owner acceptance
-- automatically; only participant and governance organizations must decide.

begin;

drop trigger if exists proposal_collaboration_owner_decision_guard on public.proposal_collaboration_approvals;

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

insert into public.audit_events (actor_id, actor_name, entity_type, entity_id, action, reason, after_data, org_id)
select draft.owner_user_id, coalesce(profile.full_name, 'Owner'), 'collaboration_approval', draft.current_revision_id::text,
  'collaboration.owner_auto_accepted',
  'Owner organization acceptance backfilled after the review-routing correction.',
  jsonb_build_object('draftId', draft.id, 'revisionId', draft.current_revision_id, 'organizationId', draft.owner_org_id),
  draft.owner_org_id
from public.proposal_collaboration_drafts draft
left join public.profiles profile on profile.id = draft.owner_user_id
where draft.current_revision_id is not null
  and draft.status in ('in_review', 'changes_requested', 'ready_to_commit')
  and not exists (
    select 1 from public.proposal_collaboration_approvals approval
    where approval.revision_id = draft.current_revision_id
      and approval.organization_id = draft.owner_org_id
      and approval.decision = 'approved'
  );

insert into public.proposal_collaboration_approvals (
  draft_id, revision_id, organization_id, decision, approved_by, reason
)
select draft.id, draft.current_revision_id, draft.owner_org_id, 'approved', draft.owner_user_id,
  'Owner organization accepted automatically when collaboration review was requested.'
from public.proposal_collaboration_drafts draft
where draft.current_revision_id is not null
  and draft.status in ('in_review', 'changes_requested', 'ready_to_commit')
on conflict (revision_id, organization_id) do update
  set decision = 'approved', approved_by = excluded.approved_by,
      reason = excluded.reason, created_at = now();

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

create trigger proposal_collaboration_owner_decision_guard
before insert or update on public.proposal_collaboration_approvals
for each row execute function public.guard_collaboration_owner_decision();

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

  select count(*) into required_count
  from public.proposal_collaboration_orgs
  where draft_id = target_draft and participation_role <> 'owner';

  select count(*) into approved_count
  from public.proposal_collaboration_orgs participating
  join public.proposal_collaboration_approvals approval
    on approval.draft_id = participating.draft_id
   and approval.organization_id = participating.org_id
   and approval.revision_id = draft_row.current_revision_id
   and approval.decision = 'approved'
  where participating.draft_id = target_draft
    and participating.participation_role <> 'owner';

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
          or not exists (
            select 1 from public.proposal_collaboration_orgs participating
            where participating.draft_id = target_draft and participating.org_id = supporting.raw_id::uuid
          )
      )
      or exists (
        select 1 from jsonb_array_elements_text(coalesce(task -> 'activitySupportingOrgIds', '[]'::jsonb)) supporting(raw_id)
        where supporting.raw_id::uuid = coalesce(nullif(task ->> 'activityPrimaryOrgId', '')::uuid, draft_row.owner_org_id)
          or not exists (
            select 1 from public.proposal_collaboration_orgs participating
            where participating.draft_id = target_draft and participating.org_id = supporting.raw_id::uuid
          )
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
        (case when missing_approvers > 0 then missing_approvers::text || ' external organization(s) have no configured approver' end),
        (case when selected_task_count = 0 then 'Select at least one task' end),
        (case when invalid_task_count > 0 then invalid_task_count::text || ' task(s) have incomplete staffing, responsibility, or review routing' end)
      ) blockers(blocker)
      where blocker is not null
    )
  );
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
    jsonb_build_object('revisionId', draft_row.current_revision_id, 'ownerOrganizationAutoAccepted', true), draft_row.owner_org_id);
  perform public.refresh_collaboration_readiness(p_draft_id);
end;
$$;

do $$
declare
  target record;
begin
  for target in
    select id from public.proposal_collaboration_drafts
    where current_revision_id is not null and status in ('in_review', 'changes_requested', 'ready_to_commit')
  loop
    perform public.refresh_collaboration_readiness(target.id);
  end loop;
end;
$$;

revoke all on function public.auto_accept_collaboration_owner() from public, anon;
revoke all on function public.guard_collaboration_owner_decision() from public, anon;
revoke all on function public.request_collaboration_review(uuid) from public, anon;
revoke all on function public.set_collaboration_source_document(uuid, text, text, text) from public, anon;
grant execute on function public.request_collaboration_review(uuid) to authenticated;
grant execute on function public.set_collaboration_source_document(uuid, text, text, text) to authenticated;

commit;
