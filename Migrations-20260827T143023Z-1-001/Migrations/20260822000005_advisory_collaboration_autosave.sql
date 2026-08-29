-- Keeps draft-mode autosave compatible with consulted and observer roles.

begin;

create or replace function public.autosave_collaboration_draft(
  p_draft_id uuid,
  p_title text,
  p_snapshot jsonb
)
returns public.proposal_collaboration_drafts
language plpgsql security definer set search_path = public
as $$
declare
  caller uuid := auth.uid();
  draft_row public.proposal_collaboration_drafts;
  item jsonb;
  target_org uuid;
  target_role text;
begin
  if not public.can_manage_collaboration_draft(p_draft_id, caller) then
    raise exception 'Only the owning organization may autosave this draft' using errcode = '42501';
  end if;
  if nullif(btrim(p_title), '') is null or jsonb_typeof(coalesce(p_snapshot, '{}'::jsonb)) <> 'object' then
    raise exception 'Draft title and snapshot are required' using errcode = '22023';
  end if;
  select * into draft_row from public.proposal_collaboration_drafts where id = p_draft_id for update;
  if draft_row.status <> 'draft' then raise exception 'Autosave is available only before collaboration review starts' using errcode = '22023'; end if;
  delete from public.proposal_collaboration_orgs where draft_id = p_draft_id and participation_role <> 'owner';
  for item in select value from jsonb_array_elements(coalesce(p_snapshot -> 'organizations', '[]'::jsonb)) loop
    target_org := nullif(item ->> 'orgId', '')::uuid;
    target_role := coalesce(nullif(item ->> 'participationRole', ''), 'participant');
    if target_org is null or target_org = draft_row.owner_org_id then continue; end if;
    if target_role not in ('participant', 'governance', 'consulted', 'observer')
       or not exists (select 1 from public.organizations where id = target_org and is_active) then
      raise exception 'Autosave contains an invalid collaboration organization' using errcode = '22023';
    end if;
    insert into public.proposal_collaboration_orgs (
      draft_id, org_id, participation_role, staffing_enabled, requested_by,
      approval_policy, quorum_count, approval_sequence, review_deadline_days
    ) values (
      p_draft_id, target_org, target_role,
      case when target_role = 'participant' then coalesce((item ->> 'staffingEnabled')::boolean, true) else false end,
      caller,
      case when item ->> 'approvalPolicy' in ('one_of', 'all', 'quorum') then item ->> 'approvalPolicy' else 'one_of' end,
      greatest(1, coalesce(nullif(item ->> 'quorumCount', '')::int, 1)),
      greatest(1, coalesce(nullif(item ->> 'sequence', '')::int, 1)),
      greatest(1, least(90, coalesce(nullif(item ->> 'reviewDeadlineDays', '')::int, 5)))
    );
  end loop;
  update public.proposal_collaboration_drafts set title = btrim(p_title), working_snapshot = p_snapshot
  where id = p_draft_id returning * into draft_row;
  return draft_row;
end;
$$;

create or replace function public.can_manage_collaboration_draft(target_draft uuid, caller_id uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
  select caller_id is not null and exists (
    select 1 from public.proposal_collaboration_drafts draft
    where draft.id = target_draft and draft.deleted_at is null
      and draft.status not in ('committed', 'archived', 'deleted')
      and (draft.owner_user_id = caller_id or public.is_organization_approver(draft.owner_org_id, caller_id))
      and public.auth_role(caller_id) <> 'super_admin'
  );
$$;

revoke all on function public.autosave_collaboration_draft(uuid, text, jsonb) from public, anon;
revoke all on function public.can_manage_collaboration_draft(uuid, uuid) from public, anon;
grant execute on function public.autosave_collaboration_draft(uuid, text, jsonb) to authenticated;
grant execute on function public.can_manage_collaboration_draft(uuid, uuid) to authenticated;

notify pgrst, 'reload schema';
commit;
