-- Supabase installs pgcrypto in its `extensions` schema. The first recovery
-- migration restored decide_task_review but referenced digest without that
-- schema qualification, so approvals reached the RPC then failed while
-- generating the server-side audit hash.

create extension if not exists pgcrypto with schema extensions;

create or replace function public.decide_task_review(
  p_task_id uuid,
  p_approve boolean,
  p_feedback text default null,
  p_audit_hash text default null
)
returns public.tasks
language plpgsql
security definer
set search_path = public
as $$
declare
  caller uuid := auth.uid();
  caller_role text;
  caller_name text;
  task_row public.tasks;
  submission public.task_submissions;
  next_status text;
  decision_hash text;
  recipient_id uuid;
begin
  if caller is null then
    raise exception 'Not authenticated' using errcode = '42501';
  end if;

  if not p_approve and coalesce(btrim(p_feedback), '') = '' then
    raise exception 'Feedback is required when requesting changes'
      using errcode = '22023';
  end if;

  select role::text, full_name
    into caller_role, caller_name
  from public.profiles
  where id = caller;

  select *
    into task_row
  from public.tasks
  where id = p_task_id
    and deleted_at is null
  for update;

  if not found then
    raise exception 'Task not found' using errcode = 'P0002';
  end if;

  if task_row.status <> 'for_review' then
    raise exception 'Task is not awaiting review' using errcode = '22023';
  end if;

  select *
    into submission
  from public.task_submissions
  where task_id = p_task_id
  order by version desc
  limit 1
  for update;

  if not found then
    raise exception 'No review submission exists' using errcode = '22023';
  end if;

  if submission.submitter_id = caller then
    raise exception 'You cannot review your own submission' using errcode = '42501';
  end if;

  if not (
    caller_role = 'super_admin'
    or task_row.reviewer_id = caller
    or task_row.backup_reviewer_id = caller
  ) then
    raise exception 'Only the assigned reviewer may decide this submission'
      using errcode = '42501';
  end if;

  next_status := case when p_approve then 'completed' else 'changes_requested' end;
  decision_hash := case when p_approve then encode(
    extensions.digest(
      p_task_id::text || ':' || submission.id::text || ':' || caller::text || ':' ||
      clock_timestamp()::text,
      'sha256'
    ),
    'hex'
  ) else null end;

  perform set_config('eflow.allow_status_write', 'on', true);
  perform set_config('eflow.review_decision_authorized', 'on', true);

  update public.tasks
  set
    status = next_status,
    percent_complete = case when p_approve then 100 else 99 end,
    feedback = nullif(btrim(p_feedback), ''),
    rejection_note = case
      when p_approve then rejection_note
      else nullif(btrim(p_feedback), '')
    end,
    rejected_at = case when p_approve then rejected_at else now() end,
    audit_hash = coalesce(decision_hash, audit_hash),
    last_activity_at = now()
  where id = p_task_id
  returning * into task_row;

  perform set_config('eflow.review_decision_authorized', 'off', true);
  perform set_config('eflow.allow_status_write', 'off', true);

  update public.task_submissions
  set
    status = case when p_approve then 'approved' else 'changes_requested' end,
    decided_by = caller,
    decided_by_name = coalesce(caller_name, 'Reviewer'),
    decision_feedback = nullif(btrim(p_feedback), ''),
    decided_at = now()
  where id = submission.id;

  insert into public.task_status_history (
    task_id, from_status, to_status, actor_id, actor_name, note
  ) values (
    p_task_id, 'for_review', next_status, caller,
    coalesce(caller_name, 'Reviewer'), nullif(btrim(p_feedback), '')
  );

  insert into public.task_activities (
    task_id, type, content, actor_id, actor_name
  ) values (
    p_task_id, next_status,
    coalesce(
      nullif(btrim(p_feedback), ''),
      case when p_approve then 'Review approved' else 'Changes requested' end
    ),
    caller, coalesce(caller_name, 'Reviewer')
  );

  insert into public.audit_events (
    actor_id, actor_name, entity_type, entity_id, action,
    reason, before_data, after_data, org_id
  ) values (
    caller, coalesce(caller_name, 'Reviewer'), 'task', p_task_id::text,
    'task.transition.' || next_status, nullif(btrim(p_feedback), ''),
    jsonb_build_object('status', 'for_review', 'submissionId', submission.id),
    jsonb_build_object('status', next_status, 'auditHash', decision_hash),
    task_row.org_id
  );

  for recipient_id in
    select distinct recipient.user_id
    from unnest(array[
      task_row.assigned_to,
      submission.submitter_id,
      task_row.recommendation_lead_id
    ]) as recipient(user_id)
    where recipient.user_id is not null
      and recipient.user_id <> caller
  loop
    insert into public.notifications (
      user_id, type, title, message, task_id, task_title,
      actor_id, actor_name, status_from, status_to, reason
    ) values (
      recipient_id,
      case when p_approve then 'completed' else 'status_change' end,
      case when p_approve then 'Task approved' else 'Changes requested' end,
      case
        when p_approve then 'Your work on "' || task_row.title || '" was approved.'
        else 'Changes were requested for "' || task_row.title || '".'
      end,
      p_task_id, task_row.title, caller, coalesce(caller_name, 'Reviewer'),
      'for_review', next_status, coalesce(nullif(btrim(p_feedback), ''), '')
    );
  end loop;

  return task_row;
end;
$$;

revoke all on function public.decide_task_review(uuid, boolean, text, text)
  from public, anon;
grant execute on function public.decide_task_review(uuid, boolean, text, text)
  to authenticated;

notify pgrst, 'reload schema';
