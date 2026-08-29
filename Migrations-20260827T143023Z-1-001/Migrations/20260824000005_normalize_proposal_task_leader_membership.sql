-- Keep the invariant that every proposed Task Leader is also a member of the
-- proposed task team. Repair only current unpublished department revisions;
-- historical and approved inter-organization revisions remain immutable.

begin;

create or replace function public.normalize_collaboration_task_teams(p_snapshot jsonb)
returns jsonb
language plpgsql
immutable
set search_path = public
as $$
declare
  normalized_tasks jsonb;
begin
  if p_snapshot is null
     or jsonb_typeof(p_snapshot) <> 'object'
     or jsonb_typeof(p_snapshot -> 'tasks') <> 'array' then
    return p_snapshot;
  end if;

  select coalesce(
    jsonb_agg(
      case
        when nullif(btrim(task_item ->> 'leadMemberId'), '') is null then task_item
        when (
          case
            when jsonb_typeof(task_item -> 'assignedMemberIds') = 'array'
              then task_item -> 'assignedMemberIds'
            else '[]'::jsonb
          end
        ) ? (task_item ->> 'leadMemberId') then task_item
        else jsonb_set(
          task_item,
          '{assignedMemberIds}',
          (
            case
              when jsonb_typeof(task_item -> 'assignedMemberIds') = 'array'
                then task_item -> 'assignedMemberIds'
              else '[]'::jsonb
            end
          ) || jsonb_build_array(task_item ->> 'leadMemberId'),
          true
        )
      end
      order by task_position
    ),
    '[]'::jsonb
  )
  into normalized_tasks
  from jsonb_array_elements(p_snapshot -> 'tasks')
    with ordinality source(task_item, task_position);

  return jsonb_set(p_snapshot, '{tasks}', normalized_tasks, true);
end;
$$;

create or replace function public.normalize_collaboration_revision_task_teams()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  new.snapshot := public.normalize_collaboration_task_teams(new.snapshot);
  return new;
end;
$$;

create or replace function public.normalize_collaboration_working_task_teams()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  new.working_snapshot := public.normalize_collaboration_task_teams(new.working_snapshot);
  return new;
end;
$$;

drop trigger if exists normalize_collaboration_revision_task_teams
  on public.proposal_collaboration_revisions;
create trigger normalize_collaboration_revision_task_teams
before insert or update of snapshot on public.proposal_collaboration_revisions
for each row execute function public.normalize_collaboration_revision_task_teams();

drop trigger if exists normalize_collaboration_working_task_teams
  on public.proposal_collaboration_drafts;
create trigger normalize_collaboration_working_task_teams
before insert or update of working_snapshot on public.proposal_collaboration_drafts
for each row execute function public.normalize_collaboration_working_task_teams();

update public.proposal_collaboration_revisions revision
set snapshot = public.normalize_collaboration_task_teams(revision.snapshot)
from public.proposal_collaboration_drafts draft
where revision.id = draft.current_revision_id
  and draft.status not in ('committed', 'archived', 'deleted')
  and not exists (
    select 1
    from public.proposal_collaboration_orgs participant
    where participant.draft_id = draft.id
      and participant.participation_role <> 'owner'
  )
  and revision.snapshot is distinct from public.normalize_collaboration_task_teams(revision.snapshot);

update public.proposal_collaboration_drafts draft
set working_snapshot = public.normalize_collaboration_task_teams(draft.working_snapshot)
where draft.status not in ('committed', 'archived', 'deleted')
  and not exists (
    select 1
    from public.proposal_collaboration_orgs participant
    where participant.draft_id = draft.id
      and participant.participation_role <> 'owner'
  )
  and draft.working_snapshot is distinct from public.normalize_collaboration_task_teams(draft.working_snapshot);

revoke all on function public.normalize_collaboration_task_teams(jsonb) from public, anon;
revoke all on function public.normalize_collaboration_revision_task_teams() from public, anon, authenticated;
revoke all on function public.normalize_collaboration_working_task_teams() from public, anon, authenticated;
grant execute on function public.normalize_collaboration_task_teams(jsonb) to authenticated;

notify pgrst, 'reload schema';

commit;
