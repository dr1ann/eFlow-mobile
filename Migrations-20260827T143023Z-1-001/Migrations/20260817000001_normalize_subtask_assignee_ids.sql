-- Normalize the legacy multi-assignee column to the same UUID-array contract
-- used by task participants. Some deployed databases created this as text[],
-- while the evidence-review functions correctly compare it with auth.uid().

drop policy if exists subtasks_update on public.subtasks;

do $$
declare
  current_udt text;
begin
  select udt_name into current_udt
  from information_schema.columns
  where table_schema = 'public'
    and table_name = 'subtasks'
    and column_name = 'assigned_to_ids';

  if current_udt is null then
    alter table public.subtasks
      add column assigned_to_ids uuid[] not null default '{}'::uuid[];
  elsif current_udt = '_text' then
    alter table public.subtasks
      alter column assigned_to_ids drop default;
    alter table public.subtasks
      alter column assigned_to_ids type uuid[]
      using coalesce(assigned_to_ids, '{}'::text[])::uuid[];
  elsif current_udt <> '_uuid' then
    raise exception 'Unsupported subtasks.assigned_to_ids type: %', current_udt;
  end if;
end;
$$;

alter table public.subtasks
  alter column assigned_to_ids set default '{}'::uuid[],
  alter column assigned_to_ids set not null;

create policy subtasks_update on public.subtasks
  for update to authenticated
  using (
    public.can_manage_subtasks(task_id, auth.uid())
    or assigned_to = auth.uid()
    or auth.uid() = any(coalesce(assigned_to_ids, '{}'::uuid[]))
  )
  with check (
    public.can_manage_subtasks(task_id, auth.uid())
    or assigned_to = auth.uid()
    or auth.uid() = any(coalesce(assigned_to_ids, '{}'::uuid[]))
  );

notify pgrst, 'reload schema';

