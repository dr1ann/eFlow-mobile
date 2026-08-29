-- A request returned for correction is no longer awaiting a decision. Release
-- its temporary hold, reacquire availability atomically on resubmission, and
-- notify the reviewer whose queue receives the corrected request.

begin;

create or replace function public.cash_request_obligation(
  request_row public.petty_cash_requests
)
returns numeric
language sql
immutable
set search_path = public
as $$
  select case
    when request_row.status in (
      'draft', 'leader_changes_requested', 'department_changes_requested',
      'rejected', 'cancelled', 'expired'
    ) then 0::numeric
    when request_row.status = 'settled' then coalesce(request_row.actual_spent, 0)
    else coalesce(request_row.approved_amount, request_row.requested_amount, 0)
  end;
$$;

create or replace function public.normalize_cash_request_reservation_window()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.status in ('pending', 'pending_leader_review', 'pending_department_approval') then
    if tg_op = 'INSERT' or new.reservation_expires_at is null or new.status is distinct from old.status then
      new.reservation_expires_at := now() + interval '7 days';
    end if;
  else
    new.reservation_expires_at := null;
  end if;
  return new;
end;
$$;

drop trigger if exists petty_cash_request_reservation_window on public.petty_cash_requests;
create trigger petty_cash_request_reservation_window
before insert or update of status on public.petty_cash_requests
for each row execute function public.normalize_cash_request_reservation_window();

update public.petty_cash_requests
set reservation_expires_at = null
where status in (
  'draft', 'leader_changes_requested', 'department_changes_requested',
  'approved', 'scheduled_for_release', 'partially_released', 'released',
  'rejected', 'cancelled', 'expired', 'liquidation_draft',
  'liquidation_submitted', 'pending_leader_liquidation_review',
  'pending_department_settlement', 'changes_requested',
  'overdue_liquidation', 'settled'
)
and reservation_expires_at is not null;

create or replace function public.notify_corrected_cash_request_reviewer()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  task_title_value text;
  actor_name_value text;
begin
  if old.status not in ('leader_changes_requested', 'department_changes_requested')
     or new.status not in ('pending_leader_review', 'pending_department_approval') then
    return new;
  end if;

  select task.title into task_title_value from public.tasks task where task.id = new.task_id;
  select profile.full_name into actor_name_value from public.profiles profile where profile.id = new.requester_id;

  if new.status = 'pending_leader_review' then
    insert into public.notifications(
      user_id, type, title, message, task_id, task_title,
      actor_id, actor_name, financial_record_id, financial_record_type
    ) values (
      new.task_leader_id, 'petty_cash_leader_review', 'Corrected cash request needs your endorsement',
      coalesce(actor_name_value, 'A contributor') || ' corrected and resubmitted ' ||
        to_char(new.requested_amount, 'FM999G999G999G990D00') || ' for ' || new.purpose ||
        ' in "' || coalesce(task_title_value, 'Funded task') || '".',
      new.task_id, coalesce(task_title_value, ''), new.requester_id,
      coalesce(actor_name_value, ''), new.id, 'petty_cash_request'
    );
  else
    insert into public.notifications(
      user_id, type, title, message, task_id, task_title,
      actor_id, actor_name, financial_record_id, financial_record_type
    )
    select approver_id, 'petty_cash_department_approval', 'Corrected cash request needs fiscal authorization',
      coalesce(actor_name_value, 'A Task Leader') || ' corrected and resubmitted ' ||
        to_char(new.requested_amount, 'FM999G999G999G990D00') || ' for ' || new.purpose ||
        ' in "' || coalesce(task_title_value, 'Funded task') || '".',
      new.task_id, coalesce(task_title_value, ''), new.requester_id,
      coalesce(actor_name_value, ''), new.id, 'petty_cash_request'
    from public.organization_approver_ids(new.org_id) approver_id
    where approver_id <> new.requester_id;
  end if;
  return new;
end;
$$;

drop trigger if exists petty_cash_request_correction_notification on public.petty_cash_requests;
create trigger petty_cash_request_correction_notification
after update of status on public.petty_cash_requests
for each row
when (old.status is distinct from new.status)
execute function public.notify_corrected_cash_request_reviewer();

notify pgrst, 'reload schema';

commit;
