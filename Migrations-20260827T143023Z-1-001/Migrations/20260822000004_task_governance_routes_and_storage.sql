-- Applies each approved snapshot task's selected governance route during the
-- existing atomic proposal commit. The trigger runs before the collaboration
-- staffing guard and ordinary Head/Assistant reciprocal router.

begin;

create or replace function public.apply_collaboration_task_governance_route()
returns trigger
language plpgsql security definer set search_path = public
as $$
declare
  revision_snapshot jsonb;
  snapshot_task jsonb;
  selected_mode text;
  selected_org uuid;
  primary_reviewer uuid;
  backup_reviewer uuid;
begin
  if new.source_collaboration_draft_id is null or new.source_collaboration_revision_id is null then return new; end if;
  select revision.snapshot into revision_snapshot from public.proposal_collaboration_revisions revision
  where revision.id = new.source_collaboration_revision_id;
  select value into snapshot_task
  from jsonb_array_elements(coalesce(revision_snapshot -> 'tasks', '[]'::jsonb)) task
  where task.value ->> 'projectId' = new.project_id
    and task.value ->> 'activityId' = new.activity_id
    and btrim(task.value ->> 'title') = btrim(new.title)
    and coalesce((task.value ->> 'enabled')::boolean, true)
  limit 1;
  if snapshot_task is null then return new; end if;
  selected_mode := nullif(snapshot_task ->> 'governanceMode', '');
  if selected_mode is null then
    selected_mode := case when exists (
      select 1 from public.proposal_collaboration_orgs participant
      where participant.draft_id = new.source_collaboration_draft_id and participant.participation_role = 'governance'
    ) then 'governance' else 'department' end;
  end if;
  if selected_mode not in ('department', 'governance', 'closeout_only') then selected_mode := 'department'; end if;
  if selected_mode <> 'governance' then
    new.governance_approval_mode := selected_mode;
    new.governance_organization_id := null;
    new.review_route_mode := 'organization_default';
    new.reviewer_id := null;
    new.backup_reviewer_id := null;
    return new;
  end if;
  selected_org := nullif(snapshot_task ->> 'governanceOrgId', '')::uuid;
  if selected_org is null then
    select participant.org_id into selected_org from public.proposal_collaboration_orgs participant
    where participant.draft_id = new.source_collaboration_draft_id and participant.participation_role = 'governance'
    order by participant.approval_sequence, participant.created_at limit 1;
  end if;
  if selected_org is null or not exists (
    select 1 from public.proposal_collaboration_orgs participant
    where participant.draft_id = new.source_collaboration_draft_id and participant.org_id = selected_org
      and participant.participation_role = 'governance'
  ) then raise exception 'Task "%" has no valid governance organization route', new.title using errcode = '22023'; end if;
  select reviewer.user_id into primary_reviewer from (
    select assignment.user_id, case assignment.assignment_role when 'primary_approver' then 0 when 'delegate' then 1 else 2 end priority
    from public.proposal_governance_assignments assignment
    join public.profiles profile on profile.id = assignment.user_id and profile.is_active
    where assignment.draft_id = new.source_collaboration_draft_id and assignment.organization_id = selected_org
      and assignment.assignment_role in ('primary_approver', 'backup_approver', 'delegate')
      and (assignment.valid_until is null or assignment.valid_until > now())
    union all
    select approver_id, 3 from public.organization_approver_ids(selected_org) approver_id
  ) reviewer where reviewer.user_id <> new.assigned_to order by reviewer.priority limit 1;
  select reviewer.user_id into backup_reviewer from (
    select assignment.user_id, case assignment.assignment_role when 'backup_approver' then 0 when 'delegate' then 1 else 2 end priority
    from public.proposal_governance_assignments assignment
    join public.profiles profile on profile.id = assignment.user_id and profile.is_active
    where assignment.draft_id = new.source_collaboration_draft_id and assignment.organization_id = selected_org
      and assignment.assignment_role in ('backup_approver', 'primary_approver', 'delegate')
      and (assignment.valid_until is null or assignment.valid_until > now())
    union all
    select approver_id, 3 from public.organization_approver_ids(selected_org) approver_id
  ) reviewer where reviewer.user_id <> new.assigned_to and reviewer.user_id <> primary_reviewer order by reviewer.priority limit 1;
  if primary_reviewer is null then raise exception 'No eligible governance reviewer exists for task "%"', new.title using errcode = '22023'; end if;
  new.governance_approval_mode := 'governance';
  new.governance_organization_id := selected_org;
  new.review_route_mode := 'governance';
  new.reviewer_id := primary_reviewer;
  new.backup_reviewer_id := backup_reviewer;
  return new;
end;
$$;

drop trigger if exists tasks_apply_collaboration_governance_route on public.tasks;
create trigger tasks_apply_collaboration_governance_route
before insert on public.tasks
for each row execute function public.apply_collaboration_task_governance_route();

create or replace function public.collaboration_storage_org_id(object_name text)
returns uuid language plpgsql immutable as $$
begin return split_part(object_name, '/', 3)::uuid;
exception when others then return null;
end;
$$;

drop policy if exists collaboration_source_insert on storage.objects;
create policy collaboration_source_insert on storage.objects
for insert to authenticated with check (
  bucket_id = 'proposal-drafts' and (
    public.can_manage_collaboration_draft(public.collaboration_storage_draft_id(name), auth.uid())
    or public.is_proposal_governance_decider(
      public.collaboration_storage_draft_id(name), public.collaboration_storage_org_id(name), auth.uid()
    )
  )
);
drop policy if exists collaboration_source_update on storage.objects;
create policy collaboration_source_update on storage.objects
for update to authenticated using (
  bucket_id = 'proposal-drafts' and (
    public.can_manage_collaboration_draft(public.collaboration_storage_draft_id(name), auth.uid())
    or public.is_proposal_governance_decider(
      public.collaboration_storage_draft_id(name), public.collaboration_storage_org_id(name), auth.uid()
    )
  )
);

create or replace function public.notify_named_governance_reviewers()
returns trigger
language plpgsql security definer set search_path = public
as $$
declare draft_row public.proposal_collaboration_drafts;
begin
  if new.requested_at is null or new.participation_role not in ('participant', 'governance') then return new; end if;
  select * into draft_row from public.proposal_collaboration_drafts where id = new.draft_id;
  insert into public.notifications (user_id, type, title, message, actor_id, actor_name, proposal_id, org_id, entity_type)
  select distinct assignment.user_id, 'collaboration_request', 'Proposal decision assigned to you',
    'You are a named ' || replace(assignment.assignment_role, '_', ' ') || ' for "' || draft_row.title || '".',
    new.requested_by, coalesce((select full_name from public.profiles where id = new.requested_by), 'Proposal owner'),
    new.draft_id::text, new.org_id, 'collaboration_draft'
  from public.proposal_governance_assignments assignment
  where assignment.draft_id = new.draft_id and assignment.organization_id = new.org_id
    and assignment.assignment_role in ('primary_approver', 'backup_approver', 'delegate')
    and assignment.user_id <> new.requested_by
    and (assignment.valid_until is null or assignment.valid_until > now())
    and not exists (
      select 1 from public.notifications notification
      where notification.user_id = assignment.user_id and notification.proposal_id = new.draft_id::text
        and notification.title = 'Proposal decision assigned to you' and notification.created_at::date = current_date
    );
  return new;
end;
$$;
drop trigger if exists proposal_collaboration_named_reviewer_notification on public.proposal_collaboration_orgs;
create trigger proposal_collaboration_named_reviewer_notification
after update of requested_at on public.proposal_collaboration_orgs
for each row execute function public.notify_named_governance_reviewers();

revoke all on function public.apply_collaboration_task_governance_route() from public, anon, authenticated;
revoke all on function public.collaboration_storage_org_id(text) from public, anon;
revoke all on function public.notify_named_governance_reviewers() from public, anon, authenticated;

notify pgrst, 'reload schema';
commit;
