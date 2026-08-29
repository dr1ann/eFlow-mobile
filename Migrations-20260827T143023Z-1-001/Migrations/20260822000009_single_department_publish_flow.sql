-- Keep department-only proposals out of the inter-department review lifecycle.
-- A proposal with only its owner organization publishes directly after the
-- existing staffing, schedule, and budget readiness checks succeed.

begin;

create or replace function public.guard_single_department_collaboration_review()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if new.status = 'in_review'
     and not exists (
       select 1
       from public.proposal_collaboration_orgs participant
       where participant.draft_id = new.id
         and participant.participation_role <> 'owner'
     ) then
    raise exception 'Single-organization proposals publish directly and do not require collaboration review'
      using errcode = '22023';
  end if;

  return new;
end;
$$;

drop trigger if exists guard_single_department_collaboration_review
  on public.proposal_collaboration_drafts;

create trigger guard_single_department_collaboration_review
before update of status on public.proposal_collaboration_drafts
for each row execute function public.guard_single_department_collaboration_review();

-- Repair department-only drafts that were previously pushed into the
-- collaboration state by the old UI. Their published revision is retained.
update public.proposal_collaboration_drafts draft
set status = 'draft',
    updated_at = now()
where draft.status in ('in_review', 'changes_requested', 'ready_to_commit')
  and draft.deleted_at is null
  and not exists (
    select 1
    from public.proposal_collaboration_orgs participant
    where participant.draft_id = draft.id
      and participant.participation_role <> 'owner'
  );

-- Remove the misleading "all organizations approved" notice generated when
-- the former review path treated zero external organizations as 0/0 approved.
delete from public.notifications notification
using public.proposal_collaboration_drafts draft
where notification.proposal_id = draft.id::text
  and notification.type = 'collaboration_ready'
  and not exists (
    select 1
    from public.proposal_collaboration_orgs participant
    where participant.draft_id = draft.id
      and participant.participation_role <> 'owner'
  );

revoke all on function public.guard_single_department_collaboration_review() from public, anon, authenticated;

notify pgrst, 'reload schema';

commit;
