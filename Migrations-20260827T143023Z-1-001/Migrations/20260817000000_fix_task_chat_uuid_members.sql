-- The canonical tasks.team_member_ids contract is uuid[]. Older deployed
-- versions of this trigger left the empty-array literal untyped, allowing the
-- PL/pgSQL expression planner to resolve it as text[] during a task roll-up.
-- Subtask progress updates touch their parent task, so that stale trigger plan
-- surfaced as: COALESCE could not convert type uuid[] to text[].

create or replace function public.sync_task_chat_channel()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_channel_id uuid;
  v_member_ids uuid[];
begin
  v_member_ids := array(
    select distinct member_id
    from unnest(
      array[new.assigned_to::uuid]
      || coalesce(new.team_member_ids::uuid[], '{}'::uuid[])
    ) as member_id
    where member_id is not null
  );

  if coalesce(cardinality(v_member_ids), 0) = 0 then
    return new;
  end if;

  select id into v_channel_id
  from public.chat_channels
  where task_id = new.id;

  if v_channel_id is null then
    insert into public.chat_channels (channel_type, task_id, name)
    values ('task', new.id, new.title)
    returning id into v_channel_id;
  else
    update public.chat_channels
    set name = new.title
    where id = v_channel_id;
  end if;

  delete from public.chat_channel_members as channel_member
  where channel_member.channel_id = v_channel_id
    and channel_member.user_id <> all(v_member_ids);

  insert into public.chat_channel_members (channel_id, user_id)
  select v_channel_id, member_id
  from unnest(v_member_ids) as member_id
  on conflict (channel_id, user_id) do nothing;

  return new;
end;
$$;

revoke all on function public.sync_task_chat_channel()
  from public, anon, authenticated;
