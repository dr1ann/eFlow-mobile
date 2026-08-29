-- Sir Gerson updates, Phase 3: atomic, audited subtask sequencing.

-- Normalize historical duplicate/gapped positions before enforcing uniqueness.
do $$
begin
  perform set_config('eflow.subtask_workflow_authorized', 'on', true);
  with ranked as (
    select id, row_number() over (
      partition by task_id order by position, created_at, id
    ) - 1 as normalized_position
    from public.subtasks
  )
  update public.subtasks subtask
  set position = ranked.normalized_position
  from ranked
  where subtask.id = ranked.id
    and subtask.position is distinct from ranked.normalized_position;
  perform set_config('eflow.subtask_workflow_authorized', 'off', true);
end;
$$;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'subtasks_task_position_unique'
      and conrelid = 'public.subtasks'::regclass
  ) then
    alter table public.subtasks
      add constraint subtasks_task_position_unique
      unique (task_id, position)
      deferrable initially immediate;
  end if;
end;
$$;

drop function if exists public.reorder_task_subtasks(uuid, uuid[]);
create function public.reorder_task_subtasks(
  p_task_id uuid,
  p_ordered_ids uuid[]
)
returns setof public.subtasks
language plpgsql
security definer
set search_path = public
as $$
declare
  caller uuid := auth.uid();
  caller_name text := '';
  parent_task public.tasks;
  existing_count integer;
  supplied_count integer;
  matching_count integer;
  before_order jsonb;
  after_order jsonb;
begin
  if caller is null then
    raise exception 'Not authenticated' using errcode = '42501';
  end if;

  select * into parent_task
  from public.tasks
  where id = p_task_id and deleted_at is null
  for update;
  if not found then
    raise exception 'Parent task was not found' using errcode = 'P0002';
  end if;
  if not public.can_manage_subtasks(p_task_id, caller) then
    raise exception 'Only the task lead or an authorized manager can reorder subtasks'
      using errcode = '42501';
  end if;
  if parent_task.archived_at is not null
     or parent_task.status in ('for_review', 'completed', 'cancelled') then
    raise exception 'Subtask order is locked while the parent task is under review, completed, cancelled, or archived'
      using errcode = '22023';
  end if;

  perform 1 from public.subtasks where task_id = p_task_id for update;
  select count(*), coalesce(jsonb_agg(
    jsonb_build_object('id', id, 'position', position)
    order by position, created_at, id
  ), '[]'::jsonb)
  into existing_count, before_order
  from public.subtasks
  where task_id = p_task_id;

  supplied_count := coalesce(cardinality(p_ordered_ids), 0);
  if supplied_count <> existing_count then
    raise exception 'The ordered list must contain every subtask exactly once'
      using errcode = '22023';
  end if;
  if exists (select 1 from unnest(p_ordered_ids) id where id is null)
     or (select count(distinct id) from unnest(p_ordered_ids) id) <> supplied_count then
    raise exception 'The ordered list contains a missing or duplicate subtask ID'
      using errcode = '22023';
  end if;

  select count(*) into matching_count
  from public.subtasks
  where task_id = p_task_id and id = any(p_ordered_ids);
  if matching_count <> existing_count then
    raise exception 'Every supplied subtask must belong to the same parent task'
      using errcode = '22023';
  end if;

  perform set_config('eflow.subtask_workflow_authorized', 'on', true);
  set constraints subtasks_task_position_unique deferred;
  update public.subtasks subtask
  set position = ordered.ordinality - 1
  from unnest(p_ordered_ids) with ordinality as ordered(id, ordinality)
  where subtask.id = ordered.id and subtask.task_id = p_task_id;
  set constraints subtasks_task_position_unique immediate;
  perform set_config('eflow.subtask_workflow_authorized', 'off', true);

  select coalesce(jsonb_agg(
    jsonb_build_object('id', id, 'position', position)
    order by position
  ), '[]'::jsonb)
  into after_order
  from public.subtasks where task_id = p_task_id;

  select coalesce(full_name, '') into caller_name
  from public.profiles where id = caller;
  insert into public.audit_events (
    actor_id, actor_name, entity_type, entity_id, action,
    before_data, after_data, org_id
  ) values (
    caller, caller_name, 'task', p_task_id::text, 'subtasks.reordered',
    jsonb_build_object('order', before_order),
    jsonb_build_object('order', after_order),
    parent_task.org_id
  );

  return query
  select * from public.subtasks
  where task_id = p_task_id
  order by position, created_at, id;
exception when others then
  perform set_config('eflow.subtask_workflow_authorized', 'off', true);
  raise;
end;
$$;

revoke all on function public.reorder_task_subtasks(uuid, uuid[]) from public, anon;
grant execute on function public.reorder_task_subtasks(uuid, uuid[]) to authenticated;
