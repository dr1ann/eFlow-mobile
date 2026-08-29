-- Removes task-level responsibility as an independent business concept while
-- retaining the existing snapshot keys required by deployed commit contracts.
-- Every task inherits the primary and supporting offices of its activity.

begin;

create or replace function public.normalize_collaboration_activity_responsibility(input_snapshot jsonb)
returns jsonb
language sql
immutable
set search_path = public
as $$
  select case
    when input_snapshot is null or jsonb_typeof(input_snapshot -> 'tasks') <> 'array' then input_snapshot
    else jsonb_set(
      input_snapshot,
      '{tasks}',
      coalesce((
        select jsonb_agg(
          task.value || jsonb_build_object(
            'activityPrimaryOrgId', coalesce(nullif(task.value ->> 'activityPrimaryOrgId', ''), task.value ->> 'primaryOrgId'),
            'activitySupportingOrgIds', case
              when task.value ? 'activitySupportingOrgIds' then coalesce(task.value -> 'activitySupportingOrgIds', '[]'::jsonb)
              else coalesce(task.value -> 'supportingOrgIds', '[]'::jsonb)
            end,
            'primaryOrgId', coalesce(nullif(task.value ->> 'activityPrimaryOrgId', ''), task.value ->> 'primaryOrgId'),
            'supportingOrgIds', case
              when task.value ? 'activitySupportingOrgIds' then coalesce(task.value -> 'activitySupportingOrgIds', '[]'::jsonb)
              else coalesce(task.value -> 'supportingOrgIds', '[]'::jsonb)
            end
          ) order by task.ordinality
        )
        from jsonb_array_elements(input_snapshot -> 'tasks') with ordinality task(value, ordinality)
      ), '[]'::jsonb),
      true
    )
  end;
$$;

create or replace function public.inherit_collaboration_activity_responsibility()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if tg_table_name = 'proposal_collaboration_drafts' then
    new.working_snapshot := public.normalize_collaboration_activity_responsibility(new.working_snapshot);
  else
    new.snapshot := public.normalize_collaboration_activity_responsibility(new.snapshot);
  end if;
  return new;
end;
$$;

drop trigger if exists proposal_drafts_inherit_activity_responsibility on public.proposal_collaboration_drafts;
create trigger proposal_drafts_inherit_activity_responsibility
before insert or update of working_snapshot on public.proposal_collaboration_drafts
for each row execute function public.inherit_collaboration_activity_responsibility();

drop trigger if exists proposal_revisions_inherit_activity_responsibility on public.proposal_collaboration_revisions;
create trigger proposal_revisions_inherit_activity_responsibility
before insert or update of snapshot on public.proposal_collaboration_revisions
for each row execute function public.inherit_collaboration_activity_responsibility();

-- Normalize editable working copies. Immutable revision history remains intact;
-- the next published revision receives the inherited responsibility model.
update public.proposal_collaboration_drafts
set working_snapshot = public.normalize_collaboration_activity_responsibility(working_snapshot)
where status in ('draft', 'changes_requested');

revoke all on function public.normalize_collaboration_activity_responsibility(jsonb) from public, anon;
grant execute on function public.normalize_collaboration_activity_responsibility(jsonb) to authenticated;

notify pgrst, 'reload schema';

commit;
