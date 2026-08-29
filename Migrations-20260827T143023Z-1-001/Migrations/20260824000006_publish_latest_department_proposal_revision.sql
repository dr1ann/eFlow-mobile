-- Department-only proposals do not have an external review step. Finalize the
-- latest autosaved working snapshot into an immutable revision and commit that
-- exact revision in one transaction.

begin;

create or replace function public.publish_department_proposal(p_draft_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  caller uuid := auth.uid();
  draft_row public.proposal_collaboration_drafts;
  current_revision public.proposal_collaboration_revisions;
  publication_revision public.proposal_collaboration_revisions;
begin
  if caller is null then
    raise exception 'Not authenticated' using errcode = '42501';
  end if;
  if not public.can_manage_collaboration_draft(p_draft_id, caller) then
    raise exception 'Only the owning organization may publish this proposal' using errcode = '42501';
  end if;

  select * into draft_row
  from public.proposal_collaboration_drafts
  where id = p_draft_id
  for update;

  if not found then
    raise exception 'Department proposal not found' using errcode = 'P0002';
  end if;
  if draft_row.status in ('committed', 'archived', 'deleted') then
    raise exception 'This department proposal can no longer be published' using errcode = '22023';
  end if;
  if exists (
    select 1
    from public.proposal_collaboration_orgs participant
    where participant.draft_id = p_draft_id
      and participant.participation_role <> 'owner'
  ) then
    raise exception 'Inter-organization proposals must complete collaboration review before publication' using errcode = '22023';
  end if;

  select * into current_revision
  from public.proposal_collaboration_revisions
  where id = draft_row.current_revision_id
    and draft_id = p_draft_id;

  if not found or current_revision.snapshot is distinct from draft_row.working_snapshot then
    select * into publication_revision
    from public.save_collaboration_revision(
      p_draft_id,
      draft_row.working_snapshot,
      'Department proposal finalized for publication'
    );
  else
    publication_revision := current_revision;
  end if;

  return public.commit_collaboration_draft(p_draft_id, publication_revision.id);
end;
$$;

revoke all on function public.publish_department_proposal(uuid) from public, anon;
grant execute on function public.publish_department_proposal(uuid) to authenticated;

notify pgrst, 'reload schema';

commit;
