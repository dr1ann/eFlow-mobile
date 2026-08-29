-- Repair governance notification routing after delegation moved to dedicated
-- assignment rows with role and validity metadata.

begin;

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
  select distinct reviewer.approver_id, 'collaboration_request', 'Proposal closeout requires review',
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
        select 1 from public.proposal_governance_signoffs signoff
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
        select 1 from public.proposal_governance_signoffs signoff
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
        select 1 from public.proposal_governance_signoffs signoff
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
        select 1 from public.proposal_governance_signoffs signoff
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

revoke all on function public.request_proposal_closeout(uuid, text) from public, anon;
revoke all on function public.run_governance_review_escalations() from public, anon;
grant execute on function public.request_proposal_closeout(uuid, text) to authenticated;
grant execute on function public.run_governance_review_escalations() to authenticated;

notify pgrst, 'reload schema';

commit;
