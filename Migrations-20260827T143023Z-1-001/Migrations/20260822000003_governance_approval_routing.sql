-- Required/advisory participation, named sign-offs, sequential approvals,
-- quorum rules, and per-task governance reviewer routing.

begin;

create or replace function public.set_collaboration_organizations(
  p_draft_id uuid,
  p_organizations jsonb,
  p_snapshot jsonb,
  p_change_summary text default 'Collaboration organizations updated'
)
returns public.proposal_collaboration_revisions
language plpgsql security definer set search_path = public
as $$
declare
  caller uuid := auth.uid();
  draft_row public.proposal_collaboration_drafts;
  item jsonb;
  target_org uuid;
  target_role text;
begin
  if not public.can_manage_collaboration_draft(p_draft_id, caller) then
    raise exception 'Only the owning organization may change collaboration scope' using errcode = '42501';
  end if;
  if jsonb_typeof(coalesce(p_organizations, '[]'::jsonb)) <> 'array' then
    raise exception 'Organizations must be an array' using errcode = '22023';
  end if;
  select * into draft_row from public.proposal_collaboration_drafts where id = p_draft_id for update;
  delete from public.proposal_collaboration_orgs where draft_id = p_draft_id and participation_role <> 'owner';
  for item in select value from jsonb_array_elements(p_organizations) loop
    target_org := nullif(item ->> 'orgId', '')::uuid;
    target_role := coalesce(nullif(item ->> 'participationRole', ''), 'participant');
    if target_org is null or target_org = draft_row.owner_org_id then continue; end if;
    if target_role not in ('participant', 'governance', 'consulted', 'observer') then
      raise exception 'Invalid collaboration participation level' using errcode = '22023';
    end if;
    if not exists (select 1 from public.organizations where id = target_org and is_active) then
      raise exception 'A selected organization is not configured or active' using errcode = '22023';
    end if;
    insert into public.proposal_collaboration_orgs (
      draft_id, org_id, participation_role, staffing_enabled, requested_by,
      approval_policy, quorum_count, approval_sequence, review_deadline_days
    ) values (
      p_draft_id, target_org, target_role,
      case when target_role in ('governance', 'consulted', 'observer') then false else coalesce((item ->> 'staffingEnabled')::boolean, true) end,
      caller,
      case when item ->> 'approvalPolicy' in ('one_of', 'all', 'quorum') then item ->> 'approvalPolicy' else 'one_of' end,
      greatest(1, coalesce(nullif(item ->> 'quorumCount', '')::int, 1)),
      greatest(1, coalesce(nullif(item ->> 'sequence', '')::int, 1)),
      greatest(1, least(90, coalesce(nullif(item ->> 'reviewDeadlineDays', '')::int, 5)))
    );
  end loop;
  return public.save_collaboration_revision(p_draft_id, p_snapshot, p_change_summary);
end;
$$;

create or replace function public.collaboration_readiness(target_draft uuid)
returns jsonb
language plpgsql stable security definer set search_path = public
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
  if not found then return jsonb_build_object('ready', false, 'blockers', jsonb_build_array('Proposal not found')); end if;
  select count(*) into required_count from public.proposal_collaboration_orgs
  where draft_id = target_draft and participation_role in ('participant', 'governance');
  select count(*) into approved_count
  from public.proposal_collaboration_orgs participant
  join public.proposal_collaboration_approvals approval
    on approval.draft_id = participant.draft_id and approval.organization_id = participant.org_id
   and approval.revision_id = draft_row.current_revision_id and approval.decision = 'approved'
  where participant.draft_id = target_draft and participant.participation_role in ('participant', 'governance');
  select count(*) into open_change_count from public.proposal_collaboration_change_requests
  where draft_id = target_draft and status = 'open';
  select count(*) into missing_approvers
  from public.proposal_collaboration_orgs participant
  where participant.draft_id = target_draft and participant.participation_role in ('participant', 'governance')
    and not exists (select 1 from public.organization_approver_ids(participant.org_id))
    and not exists (
      select 1 from public.proposal_governance_assignments assignment
      where assignment.draft_id = target_draft and assignment.organization_id = participant.org_id
        and assignment.assignment_role in ('primary_approver', 'backup_approver', 'delegate')
        and (assignment.valid_until is null or assignment.valid_until > now())
    );
  select count(*) into selected_task_count
  from jsonb_array_elements(coalesce(draft_row.working_snapshot -> 'tasks', '[]'::jsonb)) task
  where coalesce((task ->> 'enabled')::boolean, true);
  select count(*) into invalid_task_count
  from jsonb_array_elements(coalesce(draft_row.working_snapshot -> 'tasks', '[]'::jsonb)) task
  where coalesce((task ->> 'enabled')::boolean, true) and (
    nullif(btrim(task ->> 'title'), '') is null
    or nullif(task ->> 'leadMemberId', '') is null
    or not (coalesce(task -> 'assignedMemberIds', '[]'::jsonb) ? coalesce(task ->> 'leadMemberId', ''))
    or not exists (
      select 1 from public.proposal_collaboration_orgs eligible
      where eligible.draft_id = target_draft
        and eligible.org_id = coalesce(nullif(task ->> 'primaryOrgId', '')::uuid, draft_row.owner_org_id)
        and eligible.staffing_enabled
    )
    or exists (
      select 1 from jsonb_array_elements_text(coalesce(task -> 'assignedMemberIds', '[]'::jsonb)) member(raw_id)
      left join public.profiles profile on profile.id = member.raw_id::uuid and profile.is_active
      where profile.id is null or not exists (
        select 1 from public.proposal_collaboration_orgs eligible
        where eligible.draft_id = target_draft and eligible.org_id = profile.org_id and eligible.staffing_enabled
      )
    )
    or (
      coalesce(nullif(task ->> 'governanceMode', ''),
        case when exists (select 1 from public.proposal_collaboration_orgs where draft_id = target_draft and participation_role = 'governance') then 'governance' else 'department' end
      ) = 'governance'
      and (
        nullif(task ->> 'governanceOrgId', '') is null
        or not exists (
          select 1 from public.proposal_collaboration_orgs governance
          where governance.draft_id = target_draft
            and governance.org_id = nullif(task ->> 'governanceOrgId', '')::uuid
            and governance.participation_role = 'governance'
            and exists (
              select 1 from (
                select assignment.user_id from public.proposal_governance_assignments assignment
                where assignment.draft_id = target_draft and assignment.organization_id = governance.org_id
                  and assignment.assignment_role in ('primary_approver', 'backup_approver', 'delegate')
                  and (assignment.valid_until is null or assignment.valid_until > now())
                union
                select approver_id from public.organization_approver_ids(governance.org_id) approver_id
              ) reviewer where reviewer.user_id <> nullif(task ->> 'leadMemberId', '')::uuid
            )
        )
      )
    )
  );
  ready := draft_row.current_revision_id is not null and selected_task_count > 0 and invalid_task_count = 0
    and approved_count = required_count and open_change_count = 0 and missing_approvers = 0
    and draft_row.status not in ('committed', 'archived', 'deleted');
  return jsonb_build_object(
    'ready', ready, 'requiredOrganizations', required_count, 'approvedOrganizations', approved_count,
    'openChangeRequests', open_change_count, 'missingApprovers', missing_approvers,
    'selectedTasks', selected_task_count, 'invalidTasks', invalid_task_count,
    'currentRevisionId', draft_row.current_revision_id,
    'blockers', (select coalesce(jsonb_agg(blocker), '[]'::jsonb) from (values
      (case when draft_row.current_revision_id is null then 'Publish a revision' end),
      (case when approved_count < required_count then (required_count - approved_count)::text || ' required organization approval(s) pending' end),
      (case when open_change_count > 0 then open_change_count::text || ' unresolved change request(s)' end),
      (case when missing_approvers > 0 then missing_approvers::text || ' required organization(s) have no decision maker' end),
      (case when selected_task_count = 0 then 'Select at least one task' end),
      (case when invalid_task_count > 0 then invalid_task_count::text || ' task(s) have incomplete staffing, responsibility, or governance routing' end)
    ) blockers(blocker) where blocker is not null)
  );
end;
$$;

create or replace function public.decide_collaboration_review(
  p_draft_id uuid,
  p_organization_id uuid,
  p_decision text,
  p_reason text default null
)
returns public.proposal_collaboration_approvals
language plpgsql security definer set search_path = public
as $$
declare
  caller uuid := auth.uid();
  draft_row public.proposal_collaboration_drafts;
  participant public.proposal_collaboration_orgs;
  approval_row public.proposal_collaboration_approvals;
  caller_name text := '';
  required_signers int := 1;
  approved_signers int := 0;
  aggregate_decision text;
begin
  if p_decision not in ('approved', 'changes_requested', 'declined') then raise exception 'Invalid review decision' using errcode = '22023'; end if;
  if p_decision <> 'approved' and nullif(btrim(p_reason), '') is null then raise exception 'A reason is required' using errcode = '22023'; end if;
  select * into participant from public.proposal_collaboration_orgs
  where draft_id = p_draft_id and org_id = p_organization_id and participation_role in ('participant', 'governance');
  if not found then raise exception 'Organization is not a required reviewer for this proposal' using errcode = '42501'; end if;
  if not public.is_proposal_governance_decider(p_draft_id, p_organization_id, caller) then
    raise exception 'Only an assigned organization decision maker may decide' using errcode = '42501';
  end if;
  select * into draft_row from public.proposal_collaboration_drafts where id = p_draft_id for update;
  if draft_row.status not in ('in_review', 'changes_requested', 'ready_to_commit') then raise exception 'Proposal is not in review' using errcode = '22023'; end if;
  if exists (
    select 1 from public.proposal_collaboration_approvals existing
    where existing.revision_id = draft_row.current_revision_id and existing.organization_id = p_organization_id
      and existing.decision = 'approved'
  ) then raise exception 'This organization already approved the current revision' using errcode = '22023'; end if;
  if exists (
    select 1 from public.proposal_collaboration_orgs earlier
    where earlier.draft_id = p_draft_id and earlier.participation_role in ('participant', 'governance')
      and earlier.approval_sequence < participant.approval_sequence
      and not exists (
        select 1 from public.proposal_collaboration_approvals decision
        where decision.revision_id = draft_row.current_revision_id and decision.organization_id = earlier.org_id and decision.decision = 'approved'
      )
  ) then raise exception 'An earlier approval stage must finish first' using errcode = '22023'; end if;

  insert into public.proposal_governance_signoffs (
    draft_id, revision_id, organization_id, user_id, decision, reason
  ) values (p_draft_id, draft_row.current_revision_id, p_organization_id, caller, p_decision, nullif(btrim(p_reason), ''))
  on conflict (revision_id, organization_id, user_id) do update
    set decision = excluded.decision, reason = excluded.reason, delegated_to = null, created_at = now();

  if p_decision <> 'approved' then
    aggregate_decision := p_decision;
  else
    select count(*) into approved_signers from public.proposal_governance_signoffs signoff
    where signoff.revision_id = draft_row.current_revision_id and signoff.organization_id = p_organization_id and signoff.decision = 'approved';
    if participant.approval_policy = 'all' then
      select greatest(1, count(*)) into required_signers from public.proposal_governance_assignments assignment
      where assignment.draft_id = p_draft_id and assignment.organization_id = p_organization_id
        and assignment.assignment_role = 'primary_approver';
    elsif participant.approval_policy = 'quorum' then required_signers := participant.quorum_count;
    else required_signers := 1;
    end if;
    if approved_signers >= required_signers then aggregate_decision := 'approved'; else aggregate_decision := null; end if;
  end if;

  if aggregate_decision is not null then
    insert into public.proposal_collaboration_approvals (
      draft_id, revision_id, organization_id, decision, approved_by, reason
    ) values (p_draft_id, draft_row.current_revision_id, p_organization_id, aggregate_decision, caller, nullif(btrim(p_reason), ''))
    on conflict (revision_id, organization_id) do update
      set decision = excluded.decision, approved_by = caller, reason = excluded.reason, created_at = now()
    returning * into approval_row;
    if aggregate_decision <> 'approved' then update public.proposal_collaboration_drafts set status = 'changes_requested' where id = p_draft_id; end if;
  else
    select * into approval_row from public.proposal_collaboration_approvals
    where revision_id = draft_row.current_revision_id and organization_id = p_organization_id;
    -- An all-signers or quorum decision may be valid without completing the
    -- organization aggregate yet. Return a transient compatibility row so the
    -- existing client receives a stable RPC shape while the stored sign-off
    -- remains the source of truth.
    if approval_row.id is null then
      approval_row.id := gen_random_uuid();
      approval_row.draft_id := p_draft_id;
      approval_row.revision_id := draft_row.current_revision_id;
      approval_row.organization_id := p_organization_id;
      approval_row.decision := p_decision;
      approval_row.approved_by := caller;
      approval_row.reason := nullif(btrim(p_reason), '');
      approval_row.created_at := now();
    end if;
  end if;
  select coalesce(full_name, 'Approver') into caller_name from public.profiles where id = caller;
  insert into public.notifications (user_id, type, title, message, actor_id, actor_name, proposal_id, org_id, entity_type)
  values (draft_row.owner_user_id, case when p_decision = 'approved' then 'collaboration_approved' else 'collaboration_change' end,
    case when aggregate_decision = 'approved' then 'Organization approved proposal' when p_decision = 'approved' then 'Governance sign-off recorded' else 'Organization returned proposal' end,
    caller_name || ' recorded ' || replace(p_decision, '_', ' ') || ' for "' || draft_row.title || '".',
    caller, caller_name, p_draft_id::text, draft_row.owner_org_id, 'collaboration_draft');
  insert into public.audit_events (actor_id, actor_name, entity_type, entity_id, action, reason, after_data, org_id)
  values (caller, caller_name, 'collaboration_approval', coalesce(approval_row.id, gen_random_uuid())::text,
    'governance.signoff_' || p_decision, nullif(btrim(p_reason), ''),
    jsonb_build_object('draftId', p_draft_id, 'revisionId', draft_row.current_revision_id,
      'organizationId', p_organization_id, 'policy', participant.approval_policy,
      'approvedSigners', approved_signers, 'requiredSigners', required_signers), draft_row.owner_org_id);
  perform public.refresh_collaboration_readiness(p_draft_id);
  return approval_row;
end;
$$;

-- Existing published tasks keep their route. This operation lets the owner
-- switch a published task between department review, a selected governance
-- organization, or proposal-closeout-only governance.
create or replace function public.set_task_governance_route(
  p_task_id uuid,
  p_mode text,
  p_governance_organization_id uuid default null
)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  caller uuid := auth.uid();
  task_row public.tasks;
  primary_reviewer uuid;
  backup_reviewer uuid;
begin
  if p_mode not in ('department', 'governance', 'closeout_only') then raise exception 'Invalid governance route' using errcode = '22023'; end if;
  select * into task_row from public.tasks where id = p_task_id for update;
  if not found or task_row.source_collaboration_draft_id is null then raise exception 'Published proposal task not found' using errcode = 'P0002'; end if;
  if not public.can_manage_proposal_delivery(task_row.source_collaboration_draft_id, caller) then raise exception 'Only the proposal owner may change review routing' using errcode = '42501'; end if;
  if task_row.status in ('for_review', 'completed', 'cancelled') then raise exception 'Review routing is locked after submission' using errcode = '22023'; end if;
  if p_mode = 'governance' then
    if not exists (
      select 1 from public.proposal_collaboration_orgs participant
      where participant.draft_id = task_row.source_collaboration_draft_id
        and participant.org_id = p_governance_organization_id and participant.participation_role = 'governance'
    ) then raise exception 'Select a governance organization participating in the proposal' using errcode = '22023'; end if;
    select reviewer.user_id into primary_reviewer from (
      select assignment.user_id, case assignment.assignment_role when 'primary_approver' then 0 when 'delegate' then 1 else 2 end priority
      from public.proposal_governance_assignments assignment
      join public.profiles profile on profile.id = assignment.user_id and profile.is_active
      where assignment.draft_id = task_row.source_collaboration_draft_id and assignment.organization_id = p_governance_organization_id
        and assignment.assignment_role in ('primary_approver', 'backup_approver', 'delegate')
        and (assignment.valid_until is null or assignment.valid_until > now())
      union all
      select approver_id, 3 from public.organization_approver_ids(p_governance_organization_id) approver_id
    ) reviewer where reviewer.user_id <> task_row.assigned_to order by reviewer.priority limit 1;
    select reviewer.user_id into backup_reviewer from (
      select assignment.user_id, case assignment.assignment_role when 'backup_approver' then 0 when 'delegate' then 1 else 2 end priority
      from public.proposal_governance_assignments assignment
      join public.profiles profile on profile.id = assignment.user_id and profile.is_active
      where assignment.draft_id = task_row.source_collaboration_draft_id and assignment.organization_id = p_governance_organization_id
        and assignment.assignment_role in ('backup_approver', 'primary_approver', 'delegate')
        and (assignment.valid_until is null or assignment.valid_until > now())
      union all
      select approver_id, 3 from public.organization_approver_ids(p_governance_organization_id) approver_id
    ) reviewer where reviewer.user_id <> task_row.assigned_to and reviewer.user_id <> primary_reviewer order by reviewer.priority limit 1;
    if primary_reviewer is null then raise exception 'No eligible governance reviewer exists for this Task Leader' using errcode = '22023'; end if;
    update public.tasks set governance_approval_mode = p_mode, governance_organization_id = p_governance_organization_id,
      review_route_mode = 'governance', reviewer_id = primary_reviewer, backup_reviewer_id = backup_reviewer where id = p_task_id;
  else
    update public.tasks set governance_approval_mode = p_mode, governance_organization_id = null,
      review_route_mode = 'organization_default', reviewer_id = null, backup_reviewer_id = null where id = p_task_id;
  end if;
end;
$$;

revoke all on function public.set_collaboration_organizations(uuid, jsonb, jsonb, text) from public, anon;
revoke all on function public.collaboration_readiness(uuid) from public, anon;
revoke all on function public.decide_collaboration_review(uuid, uuid, text, text) from public, anon;
revoke all on function public.set_task_governance_route(uuid, text, uuid) from public, anon;
grant execute on function public.set_collaboration_organizations(uuid, jsonb, jsonb, text) to authenticated;
grant execute on function public.collaboration_readiness(uuid) to authenticated;
grant execute on function public.decide_collaboration_review(uuid, uuid, text, text) to authenticated;
grant execute on function public.set_task_governance_route(uuid, text, uuid) to authenticated;

notify pgrst, 'reload schema';
commit;
