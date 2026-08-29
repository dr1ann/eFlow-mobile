-- Every saved subtask progress update should proactively notify the resolved
-- Team Leader (or task reviewer fallback). Evidence submission already has its
-- own approval-needed notification, so this trigger covers 0-99% updates.

create or replace function public.notify_subtask_progress_leader()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  subtask_row public.subtasks;
  task_row public.tasks;
  recipient_id uuid;
  detail_text text;
begin
  select * into subtask_row
  from public.subtasks
  where id = new.subtask_id;
  if not found then return new; end if;

  select * into task_row
  from public.tasks
  where id = new.task_id and deleted_at is null;
  if not found then return new; end if;

  recipient_id := public.resolve_subtask_reviewer(task_row, new.author_id);
  if recipient_id is null or recipient_id = new.author_id then return new; end if;

  detail_text := concat_ws(
    ' · ',
    nullif(btrim(new.note), ''),
    case
      when nullif(btrim(new.blocker_category), '') is not null
       and new.blocker_category <> 'None'
        then 'Blocker: ' || new.blocker_category ||
          case when nullif(btrim(new.blocker), '') is not null then ' — ' || btrim(new.blocker) else '' end
      else null
    end,
    case when nullif(btrim(new.next_step), '') is not null then 'Next: ' || btrim(new.next_step) else null end,
    case when nullif(btrim(new.attachment_name), '') is not null then 'Attachment: ' || new.attachment_name else null end
  );

  insert into public.notifications (
    user_id, type, title, message, task_id, task_title,
    actor_id, actor_name, status_from, status_to, reason
  ) values (
    recipient_id,
    'status_change',
    'Subtask progress updated',
    coalesce(new.author_name, 'A team member') || ' updated "' ||
      subtask_row.title || '" to ' || new.percent_complete || '%.' ||
      case when detail_text <> '' then ' ' || detail_text else '' end,
    task_row.id,
    task_row.title,
    new.author_id,
    coalesce(new.author_name, 'Team member'),
    '',
    new.percent_complete || '%',
    ''
  );

  return new;
end;
$$;

drop trigger if exists subtask_progress_notify_leader
  on public.subtask_progress_updates;
create trigger subtask_progress_notify_leader
after insert on public.subtask_progress_updates
for each row execute function public.notify_subtask_progress_leader();

revoke all on function public.notify_subtask_progress_leader()
  from public, anon, authenticated;
