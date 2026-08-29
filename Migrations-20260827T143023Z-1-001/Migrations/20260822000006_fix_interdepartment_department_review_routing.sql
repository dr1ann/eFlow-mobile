-- Keeps non-governed collaboration task review inside the organization that
-- owns the task. The proposal creator is not a cross-organization reviewer.

begin;

create or replace function public.route_organization_leadership_review()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  org_head uuid;
  org_assistant uuid;
  expected_reviewer uuid;
  expected_backup uuid;
  expected_label text;
  reviewer_active boolean;
  backup_active boolean;
begin
  -- Explicit people and governance organizations remain authoritative.
  if coalesce(new.review_route_mode, 'organization_default') in ('explicit', 'governance') then
    return new;
  end if;
  if new.org_id is null or new.assigned_to is null then return new; end if;

  select head_user_id, assistant_head_user_id
    into org_head, org_assistant
  from public.organizations
  where id = new.org_id;

  if new.assigned_to = org_head then
    expected_reviewer := org_assistant;
    expected_label := 'Assistant Head';
  elsif new.assigned_to = org_assistant then
    expected_reviewer := org_head;
    expected_label := 'Head';
  elsif new.source_collaboration_draft_id is not null then
    -- For an inter-department proposal, ordinary employee/Team Leader work is
    -- reviewed by the Head of the task's primary organization, never by the
    -- user who happened to publish the overall proposal.
    expected_reviewer := org_head;
    expected_backup := org_assistant;
    expected_label := 'Head';
  else
    return new;
  end if;

  if expected_reviewer is not null then
    select is_active into reviewer_active from public.profiles where id = expected_reviewer;
  end if;
  if expected_backup is not null then
    select is_active into backup_active from public.profiles where id = expected_backup;
  end if;

  if expected_reviewer is null or expected_reviewer = new.assigned_to
     or not coalesce(reviewer_active, false) then
    new.reviewer_id := null;
    new.backup_reviewer_id := null;
    if new.status = 'for_review' then
      raise exception 'Assign an active % for the task''s responsible organization before submitting', expected_label
        using errcode = '22023';
    end if;
    return new;
  end if;

  new.reviewer_id := expected_reviewer;
  new.backup_reviewer_id := case
    when coalesce(backup_active, false)
      and expected_backup <> new.assigned_to
      and expected_backup <> expected_reviewer
    then expected_backup
    else null
  end;
  return new;
end;
$$;

-- Correct already-published, still-active collaboration tasks when the
-- responsible organization has the required active reciprocal reviewer.
-- Assigning the column to itself deliberately invokes the routing trigger.
update public.tasks task
set reviewer_id = task.reviewer_id
from public.organizations organization
where task.org_id = organization.id
  and task.source_collaboration_draft_id is not null
  and coalesce(task.review_route_mode, 'organization_default') = 'organization_default'
  and task.deleted_at is null
  and task.archived_at is null
  and task.status not in ('completed', 'cancelled')
  and exists (
    select 1 from public.profiles reviewer
    where reviewer.id = case
      when task.assigned_to = organization.head_user_id then organization.assistant_head_user_id
      else organization.head_user_id
    end
      and reviewer.is_active
  );

notify pgrst, 'reload schema';

commit;
