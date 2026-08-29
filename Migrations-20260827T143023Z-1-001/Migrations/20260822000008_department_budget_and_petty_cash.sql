-- Department-only fiscal budgets, proposal commitments, work allocations,
-- petty-cash reservations, and immutable liquidation attempts.

create table if not exists public.department_fiscal_budgets (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organizations(id) on delete restrict,
  fiscal_year int not null check (fiscal_year between 2000 and 2200),
  status text not null default 'draft' check (status in ('draft', 'locked', 'closed')),
  approved_amount numeric(16,2) not null default 0 check (approved_amount >= 0),
  petty_cash_limit numeric(16,2) not null default 30000 check (petty_cash_limit >= 0),
  petty_cash_request_limit numeric(16,2) not null default 5000 check (petty_cash_request_limit > 0),
  underutilization_threshold numeric(5,2) not null default 75 check (underutilization_threshold between 0 and 100),
  notes text,
  created_by uuid not null references public.profiles(id) on delete restrict,
  locked_by uuid references public.profiles(id) on delete restrict,
  locked_at timestamptz,
  closed_by uuid references public.profiles(id) on delete restrict,
  closed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (org_id, fiscal_year)
);

create table if not exists public.department_budget_lines (
  id uuid primary key default gen_random_uuid(),
  fiscal_budget_id uuid not null references public.department_fiscal_budgets(id) on delete cascade,
  expense_class text not null,
  category text not null,
  particular text not null,
  approved_amount numeric(16,2) not null check (approved_amount >= 0),
  fund_source text not null,
  position int not null default 0,
  created_by uuid not null references public.profiles(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.budget_commitments (
  id uuid primary key default gen_random_uuid(),
  fiscal_budget_id uuid not null references public.department_fiscal_budgets(id) on delete restrict,
  proposal_draft_id uuid not null references public.proposal_collaboration_drafts(id) on delete restrict,
  proposal_revision_id uuid references public.proposal_collaboration_revisions(id) on delete restrict,
  title text not null,
  amount numeric(16,2) not null check (amount >= 0),
  status text not null default 'active' check (status in ('active', 'released', 'closed')),
  created_by uuid not null references public.profiles(id) on delete restrict,
  released_by uuid references public.profiles(id) on delete restrict,
  released_at timestamptz,
  release_reason text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (proposal_draft_id)
);

create table if not exists public.work_budget_allocations (
  id uuid primary key default gen_random_uuid(),
  commitment_id uuid not null references public.budget_commitments(id) on delete restrict,
  task_id uuid not null references public.tasks(id) on delete restrict,
  subtask_id uuid references public.subtasks(id) on delete restrict,
  amount numeric(16,2) not null check (amount > 0),
  status text not null default 'pending' check (status in ('pending', 'approved', 'rejected', 'cancelled')),
  reason text not null,
  requested_by uuid not null references public.profiles(id) on delete restrict,
  decided_by uuid references public.profiles(id) on delete restrict,
  decision_reason text,
  requested_at timestamptz not null default now(),
  decided_at timestamptz,
  updated_at timestamptz not null default now()
);

create unique index if not exists work_budget_task_active_uni
  on public.work_budget_allocations(commitment_id, task_id)
  where subtask_id is null and status in ('pending', 'approved');
create unique index if not exists work_budget_subtask_active_uni
  on public.work_budget_allocations(commitment_id, subtask_id)
  where subtask_id is not null and status in ('pending', 'approved');

create table if not exists public.petty_cash_requests (
  id uuid primary key default gen_random_uuid(),
  request_number bigint generated always as identity,
  fiscal_budget_id uuid not null references public.department_fiscal_budgets(id) on delete restrict,
  commitment_id uuid not null references public.budget_commitments(id) on delete restrict,
  allocation_id uuid not null references public.work_budget_allocations(id) on delete restrict,
  org_id uuid not null references public.organizations(id) on delete restrict,
  task_id uuid not null references public.tasks(id) on delete restrict,
  subtask_id uuid references public.subtasks(id) on delete restrict,
  requester_id uuid not null references public.profiles(id) on delete restrict,
  purpose text not null,
  requested_amount numeric(16,2) not null check (requested_amount > 0),
  needed_by date,
  status text not null default 'pending' check (status in (
    'pending', 'approved', 'rejected', 'cancelled',
    'liquidation_submitted', 'changes_requested', 'settled'
  )),
  approved_amount numeric(16,2),
  approved_by uuid references public.profiles(id) on delete restrict,
  approval_reason text,
  decided_at timestamptz,
  actual_spent numeric(16,2),
  returned_amount numeric(16,2),
  settled_by uuid references public.profiles(id) on delete restrict,
  settled_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.petty_cash_liquidations (
  id uuid primary key default gen_random_uuid(),
  request_id uuid not null references public.petty_cash_requests(id) on delete restrict,
  version int not null check (version > 0),
  declared_spent numeric(16,2) not null check (declared_spent >= 0),
  returned_amount numeric(16,2) not null check (returned_amount >= 0),
  note text not null,
  status text not null default 'pending' check (status in ('pending', 'approved', 'changes_requested')),
  submitted_by uuid not null references public.profiles(id) on delete restrict,
  submitted_at timestamptz not null default now(),
  decided_by uuid references public.profiles(id) on delete restrict,
  decision_reason text,
  decided_at timestamptz,
  unique (request_id, version)
);

create table if not exists public.petty_cash_receipts (
  id uuid primary key default gen_random_uuid(),
  liquidation_id uuid not null references public.petty_cash_liquidations(id) on delete restrict,
  vendor text not null,
  receipt_number text,
  receipt_date date not null,
  description text not null,
  amount numeric(16,2) not null check (amount > 0),
  file_name text not null,
  file_path text not null,
  mime_type text not null,
  file_size bigint not null check (file_size >= 0),
  created_by uuid not null references public.profiles(id) on delete restrict,
  created_at timestamptz not null default now()
);

create table if not exists public.budget_ledger_entries (
  id uuid primary key default gen_random_uuid(),
  fiscal_budget_id uuid not null references public.department_fiscal_budgets(id) on delete restrict,
  org_id uuid not null references public.organizations(id) on delete restrict,
  commitment_id uuid references public.budget_commitments(id) on delete restrict,
  allocation_id uuid references public.work_budget_allocations(id) on delete restrict,
  petty_cash_request_id uuid references public.petty_cash_requests(id) on delete restrict,
  entry_type text not null check (entry_type in (
    'budget_locked', 'proposal_committed', 'proposal_released',
    'allocation_approved', 'petty_cash_reserved', 'petty_cash_released',
    'expense_posted', 'cash_returned'
  )),
  amount numeric(16,2) not null check (amount >= 0),
  description text not null,
  actor_id uuid references public.profiles(id) on delete restrict,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index if not exists department_budget_org_year_idx on public.department_fiscal_budgets(org_id, fiscal_year desc);
create index if not exists department_budget_lines_budget_idx on public.department_budget_lines(fiscal_budget_id, position);
create index if not exists budget_commitments_budget_idx on public.budget_commitments(fiscal_budget_id, status);
create index if not exists work_budget_task_idx on public.work_budget_allocations(task_id, status);
create index if not exists work_budget_subtask_idx on public.work_budget_allocations(subtask_id, status);
create index if not exists petty_cash_request_org_idx on public.petty_cash_requests(org_id, status, created_at desc);
create index if not exists petty_cash_request_requester_idx on public.petty_cash_requests(requester_id, created_at desc);
create index if not exists petty_cash_liquidation_request_idx on public.petty_cash_liquidations(request_id, version desc);
create index if not exists petty_cash_receipts_liquidation_idx on public.petty_cash_receipts(liquidation_id);
create index if not exists budget_ledger_budget_idx on public.budget_ledger_entries(fiscal_budget_id, created_at desc);

create or replace function public.is_department_budget_head(target_org uuid, caller_id uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.profiles p
    join public.organizations o on o.id = target_org
    where p.id = caller_id and p.is_active
      and p.org_id = target_org
      and p.role::text in ('dept_head', 'department_head')
      and o.head_user_id = p.id
  );
$$;

create or replace function public.is_department_budget_approver(target_org uuid, caller_id uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.profiles p
    join public.organizations o on o.id = target_org
    where p.id = caller_id and p.is_active
      and p.org_id = target_org
      and p.role::text in ('dept_head', 'department_head', 'assistant_head')
      and (o.head_user_id = p.id or o.assistant_head_user_id = p.id)
  );
$$;

create or replace function public.can_view_department_budget(target_org uuid, caller_id uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select caller_id is not null and (
    exists (
      select 1
      from public.profiles profile
      where profile.id = caller_id
        and profile.is_active
        and profile.org_id = target_org
    )
    or public.is_organization_member(target_org, caller_id)
    or public.can_access_org(caller_id, target_org, 'read')
  );
$$;

create or replace function public.save_department_fiscal_budget(
  p_org_id uuid,
  p_fiscal_year int,
  p_petty_cash_limit numeric,
  p_request_limit numeric,
  p_underutilization_threshold numeric,
  p_notes text,
  p_lines jsonb
) returns uuid language plpgsql security definer set search_path = public as $$
declare
  caller uuid := auth.uid();
  budget_id uuid;
  line jsonb;
  total numeric := 0;
begin
  if not public.is_department_budget_head(p_org_id, caller) then
    raise exception 'Only the assigned Department Head can create the annual budget' using errcode = '42501';
  end if;
  if p_fiscal_year < 2000 or p_fiscal_year > 2200 then raise exception 'Invalid fiscal year' using errcode = '22023'; end if;
  if p_petty_cash_limit < 0 or p_request_limit <= 0 or p_request_limit > p_petty_cash_limit then
    raise exception 'Petty-cash limits are invalid' using errcode = '22023';
  end if;
  if p_underutilization_threshold < 0 or p_underutilization_threshold > 100 then
    raise exception 'Utilization threshold must be from 0 to 100' using errcode = '22023';
  end if;
  if jsonb_typeof(coalesce(p_lines, '[]'::jsonb)) <> 'array' or jsonb_array_length(coalesce(p_lines, '[]'::jsonb)) = 0 then
    raise exception 'Add at least one annual budget line' using errcode = '22023';
  end if;
  for line in select value from jsonb_array_elements(p_lines) loop
    if nullif(btrim(line ->> 'expenseClass'), '') is null or nullif(btrim(line ->> 'category'), '') is null or nullif(btrim(line ->> 'particular'), '') is null
       or nullif(btrim(line ->> 'fundSource'), '') is null then
      raise exception 'Every budget line needs an expense class, category, particular, and fund source' using errcode = '22023';
    end if;
    if coalesce((line ->> 'amount')::numeric, -1) < 0 then raise exception 'Budget amounts cannot be negative' using errcode = '22023'; end if;
    total := total + (line ->> 'amount')::numeric;
  end loop;
  select id into budget_id from public.department_fiscal_budgets
  where org_id = p_org_id and fiscal_year = p_fiscal_year for update;
  if budget_id is not null and exists (select 1 from public.department_fiscal_budgets where id = budget_id and status <> 'draft') then
    raise exception 'The annual budget is locked and cannot be edited' using errcode = '22023';
  end if;
  if budget_id is null then
    insert into public.department_fiscal_budgets (
      org_id, fiscal_year, approved_amount, petty_cash_limit,
      petty_cash_request_limit, underutilization_threshold, notes, created_by
    ) values (
      p_org_id, p_fiscal_year, total, p_petty_cash_limit,
      p_request_limit, p_underutilization_threshold, nullif(btrim(p_notes), ''), caller
    ) returning id into budget_id;
  else
    update public.department_fiscal_budgets set
      approved_amount = total,
      petty_cash_limit = p_petty_cash_limit,
      petty_cash_request_limit = p_request_limit,
      underutilization_threshold = p_underutilization_threshold,
      notes = nullif(btrim(p_notes), ''),
      updated_at = now()
    where id = budget_id;
    delete from public.department_budget_lines where fiscal_budget_id = budget_id;
  end if;
  for line in select value from jsonb_array_elements(p_lines) loop
    insert into public.department_budget_lines (
      fiscal_budget_id, expense_class, category, particular, approved_amount, fund_source, position, created_by
    ) values (
      budget_id, btrim(line ->> 'expenseClass'), btrim(line ->> 'category'), btrim(line ->> 'particular'),
      (line ->> 'amount')::numeric, btrim(line ->> 'fundSource'),
      coalesce((line ->> 'position')::int, 0), caller
    );
  end loop;
  insert into public.audit_events(actor_id, actor_name, entity_type, entity_id, action, after_data, org_id)
  select caller, coalesce(full_name, 'Department Head'), 'department_budget', budget_id::text,
    'department_budget.saved', jsonb_build_object('fiscalYear', p_fiscal_year, 'amount', total), p_org_id
  from public.profiles where id = caller;
  return budget_id;
end;
$$;

create or replace function public.lock_department_fiscal_budget(p_budget_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare caller uuid := auth.uid(); budget public.department_fiscal_budgets;
begin
  select * into budget from public.department_fiscal_budgets where id = p_budget_id for update;
  if not found then raise exception 'Annual budget not found' using errcode = 'P0002'; end if;
  if not public.is_department_budget_head(budget.org_id, caller) then raise exception 'Only the Department Head can lock this budget' using errcode = '42501'; end if;
  if budget.status <> 'draft' then raise exception 'This annual budget is already locked' using errcode = '22023'; end if;
  if budget.approved_amount <= 0 then raise exception 'The annual budget total must be greater than zero' using errcode = '22023'; end if;
  update public.department_fiscal_budgets set status = 'locked', locked_by = caller, locked_at = now(), updated_at = now() where id = p_budget_id;
  insert into public.budget_ledger_entries(fiscal_budget_id, org_id, entry_type, amount, description, actor_id)
  values (budget.id, budget.org_id, 'budget_locked', budget.approved_amount, 'Annual department budget locked', caller);
  insert into public.audit_events(actor_id, actor_name, entity_type, entity_id, action, after_data, org_id)
  select caller, coalesce(full_name, 'Department Head'), 'department_budget', budget.id::text,
    'department_budget.locked', jsonb_build_object('fiscalYear', budget.fiscal_year, 'amount', budget.approved_amount), budget.org_id
  from public.profiles where id = caller;
end;
$$;

create or replace function public.commit_single_department_proposal_budget()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  budget_json jsonb;
  line jsonb;
  total numeric := 0;
  line_total numeric := 0;
  year int;
  fiscal public.department_fiscal_budgets;
  already_committed numeric := 0;
  commitment_id uuid;
begin
  if new.status <> 'committed' or old.status = 'committed' then return new; end if;
  if new.source_type <> 'manual' then return new; end if;
  if exists (
    select 1 from public.proposal_collaboration_orgs
    where draft_id = new.id and participation_role <> 'owner'
  ) then return new; end if;
  select revision.snapshot -> 'budget'
    into budget_json
  from public.proposal_collaboration_revisions revision
  where revision.id = new.current_revision_id and revision.draft_id = new.id;
  if budget_json is null or jsonb_typeof(budget_json) <> 'object' then
    raise exception 'Add a proposal budget before publishing this department-only plan' using errcode = '22023';
  end if;
  total := coalesce((budget_json ->> 'totalAmount')::numeric, 0);
  year := coalesce((budget_json ->> 'fiscalYear')::int, extract(year from now())::int);
  if total <= 0 then raise exception 'Set a proposal budget greater than zero before publishing' using errcode = '22023'; end if;
  if jsonb_typeof(coalesce(budget_json -> 'lines', '[]'::jsonb)) <> 'array' then
    raise exception 'Proposal budget lines are invalid' using errcode = '22023';
  end if;
  for line in select value from jsonb_array_elements(coalesce(budget_json -> 'lines', '[]'::jsonb)) loop
    if nullif(btrim(line ->> 'expenseClass'), '') is null
       or nullif(btrim(line ->> 'category'), '') is null
       or nullif(btrim(line ->> 'particular'), '') is null
       or nullif(btrim(line ->> 'fundSource'), '') is null then
      raise exception 'Every proposal budget line needs an expense class, category, particular, and fund source' using errcode = '22023';
    end if;
    if coalesce((line ->> 'amount')::numeric, -1) < 0 then
      raise exception 'Proposal budget line amounts cannot be negative' using errcode = '22023';
    end if;
    line_total := line_total + coalesce((line ->> 'amount')::numeric, 0);
  end loop;
  if abs(line_total - total) > 0.009 then raise exception 'Proposal budget total does not match its line items' using errcode = '22023'; end if;
  select * into fiscal from public.department_fiscal_budgets
  where org_id = new.owner_org_id and fiscal_year = year and status = 'locked' for update;
  if not found then
    raise exception 'No locked % department budget exists. Save this proposal as an unfunded draft.', year using errcode = '22023';
  end if;
  select coalesce(sum(amount), 0) into already_committed
  from public.budget_commitments where fiscal_budget_id = fiscal.id and status = 'active';
  if already_committed + total > fiscal.approved_amount then
    raise exception 'Insufficient department budget. Shortfall: %',
      to_char((already_committed + total) - fiscal.approved_amount, 'FM999G999G999G990D00') using errcode = '22023';
  end if;
  insert into public.budget_commitments(
    fiscal_budget_id, proposal_draft_id, proposal_revision_id, title, amount, created_by
  ) values (
    fiscal.id, new.id, new.current_revision_id, new.title, total, auth.uid()
  ) returning id into commitment_id;
  insert into public.budget_ledger_entries(
    fiscal_budget_id, org_id, commitment_id, entry_type, amount, description, actor_id,
    metadata
  ) values (
    fiscal.id, fiscal.org_id, commitment_id, 'proposal_committed', total,
    'Budget reserved for published proposal: ' || new.title, auth.uid(),
    jsonb_build_object('proposalDraftId', new.id, 'revisionId', new.current_revision_id)
  );
  return new;
end;
$$;

drop trigger if exists proposal_department_budget_commit on public.proposal_collaboration_drafts;
create trigger proposal_department_budget_commit
before update of status on public.proposal_collaboration_drafts
for each row execute function public.commit_single_department_proposal_budget();

create or replace function public.create_work_budget_allocation(
  p_task_id uuid,
  p_subtask_id uuid,
  p_amount numeric,
  p_reason text
) returns uuid language plpgsql security definer set search_path = public as $$
declare
  caller uuid := auth.uid();
  task public.tasks;
  commitment public.budget_commitments;
  allocation_id uuid;
  parent_amount numeric := 0;
  allocated numeric := 0;
  initial_status text;
begin
  if p_amount <= 0 or nullif(btrim(p_reason), '') is null then raise exception 'Enter a positive amount and reason' using errcode = '22023'; end if;
  select * into task from public.tasks where id = p_task_id;
  if not found then raise exception 'Task not found' using errcode = 'P0002'; end if;
  select c.* into commitment from public.budget_commitments c
  join public.department_fiscal_budgets b on b.id = c.fiscal_budget_id
  where c.proposal_draft_id = task.source_collaboration_draft_id and c.status = 'active' and b.org_id = task.org_id
  for update of c;
  if not found then raise exception 'This task has no active department proposal budget' using errcode = '22023'; end if;
  if p_subtask_id is not null and not exists (select 1 from public.subtasks s where s.id = p_subtask_id and s.task_id = p_task_id) then
    raise exception 'Subtask does not belong to this task' using errcode = '22023';
  end if;
  if p_subtask_id is null then
    if not public.is_department_budget_approver(task.org_id, caller) then raise exception 'Only the Head or Assistant Head can allocate a task budget' using errcode = '42501'; end if;
    select coalesce(sum(amount), 0) into allocated from public.work_budget_allocations
      where commitment_id = commitment.id and subtask_id is null and status = 'approved';
    if allocated + p_amount > commitment.amount then raise exception 'The proposal does not have enough unallocated budget' using errcode = '22023'; end if;
    initial_status := 'approved';
  else
    if not public.is_department_budget_approver(task.org_id, caller)
       and caller is distinct from coalesce(task.recommendation_lead_id, task.assigned_to) then
      raise exception 'Only the Task Leader can propose a subtask budget' using errcode = '42501';
    end if;
    select amount into parent_amount from public.work_budget_allocations
      where commitment_id = commitment.id and task_id = p_task_id and subtask_id is null and status = 'approved';
    if parent_amount is null then raise exception 'Allocate the parent task budget first' using errcode = '22023'; end if;
    select coalesce(sum(amount), 0) into allocated from public.work_budget_allocations
      where commitment_id = commitment.id and task_id = p_task_id and subtask_id is not null and status = 'approved';
    if allocated + p_amount > parent_amount then raise exception 'The task does not have enough unallocated budget' using errcode = '22023'; end if;
    initial_status := case when public.is_department_budget_approver(task.org_id, caller) then 'approved' else 'pending' end;
  end if;
  insert into public.work_budget_allocations(
    commitment_id, task_id, subtask_id, amount, status, reason, requested_by,
    decided_by, decided_at
  ) values (
    commitment.id, p_task_id, p_subtask_id, p_amount, initial_status, btrim(p_reason), caller,
    case when initial_status = 'approved' then caller end,
    case when initial_status = 'approved' then now() end
  ) returning id into allocation_id;
  if initial_status = 'approved' then
    insert into public.budget_ledger_entries(fiscal_budget_id, org_id, commitment_id, allocation_id, entry_type, amount, description, actor_id)
    values (commitment.fiscal_budget_id, task.org_id, commitment.id, allocation_id, 'allocation_approved', p_amount,
      case when p_subtask_id is null then 'Task budget allocated' else 'Subtask budget allocated' end, caller);
  else
    insert into public.notifications(user_id, type, title, message, task_id, task_title, actor_id, actor_name)
    select approver_id, 'budget_approval', 'Subtask budget approval needed',
      coalesce(p.full_name, 'A Task Leader') || ' requested ' || to_char(p_amount, 'FM999G999G999G990D00') || ' for a subtask.',
      task.id, task.title, caller, coalesce(p.full_name, '')
    from public.organization_approver_ids(task.org_id) approver_id
    left join public.profiles p on p.id = caller
    where approver_id <> caller;
  end if;
  return allocation_id;
end;
$$;

create or replace function public.decide_work_budget_allocation(
  p_allocation_id uuid,
  p_approve boolean,
  p_reason text
) returns void language plpgsql security definer set search_path = public as $$
declare caller uuid := auth.uid(); allocation public.work_budget_allocations; task public.tasks; parent_amount numeric; allocated numeric;
begin
  select * into allocation from public.work_budget_allocations where id = p_allocation_id for update;
  if not found then raise exception 'Allocation request not found' using errcode = 'P0002'; end if;
  select * into task from public.tasks where id = allocation.task_id;
  if not public.is_department_budget_approver(task.org_id, caller) then raise exception 'Only the Head or Assistant Head can decide this allocation' using errcode = '42501'; end if;
  if allocation.status <> 'pending' then raise exception 'This allocation has already been decided' using errcode = '22023'; end if;
  if caller = allocation.requested_by then raise exception 'You cannot approve your own allocation request' using errcode = '42501'; end if;
  if p_approve then
    select amount into parent_amount from public.work_budget_allocations
      where commitment_id = allocation.commitment_id and task_id = allocation.task_id and subtask_id is null and status = 'approved'
      for update;
    select coalesce(sum(amount), 0) into allocated from public.work_budget_allocations
      where commitment_id = allocation.commitment_id and task_id = allocation.task_id
        and subtask_id is not null and status = 'approved';
    if parent_amount is null or allocated + allocation.amount > parent_amount then raise exception 'The task budget is no longer sufficient' using errcode = '22023'; end if;
  end if;
  update public.work_budget_allocations set status = case when p_approve then 'approved' else 'rejected' end,
    decided_by = caller, decision_reason = nullif(btrim(p_reason), ''), decided_at = now(), updated_at = now()
  where id = allocation.id;
  if p_approve then
    insert into public.budget_ledger_entries(fiscal_budget_id, org_id, commitment_id, allocation_id, entry_type, amount, description, actor_id)
    select c.fiscal_budget_id, task.org_id, c.id, allocation.id, 'allocation_approved', allocation.amount, 'Subtask budget allocation approved', caller
    from public.budget_commitments c where c.id = allocation.commitment_id;
  end if;
  insert into public.notifications(user_id, type, title, message, task_id, task_title, actor_id, actor_name, reason)
  select allocation.requested_by, 'budget_decision', case when p_approve then 'Subtask budget approved' else 'Subtask budget declined' end,
    'Your ' || to_char(allocation.amount, 'FM999G999G999G990D00') || ' subtask budget request was ' || case when p_approve then 'approved.' else 'declined.' end,
    task.id, task.title, caller, coalesce(full_name, ''), coalesce(p_reason, '') from public.profiles where id = caller;
end;
$$;

create or replace function public.create_petty_cash_request(
  p_allocation_id uuid,
  p_amount numeric,
  p_purpose text,
  p_needed_by date
) returns uuid language plpgsql security definer set search_path = public as $$
declare
  caller uuid := auth.uid(); allocation public.work_budget_allocations; commitment public.budget_commitments;
  budget public.department_fiscal_budgets; task public.tasks; request_id uuid; used numeric := 0; allocated_used numeric := 0;
begin
  select * into allocation from public.work_budget_allocations where id = p_allocation_id and status = 'approved';
  if not found then raise exception 'Choose an approved task or subtask budget allocation' using errcode = '22023'; end if;
  select * into commitment from public.budget_commitments where id = allocation.commitment_id and status = 'active';
  if not found then raise exception 'The proposal budget is no longer active' using errcode = '22023'; end if;
  select * into budget from public.department_fiscal_budgets where id = commitment.fiscal_budget_id and status = 'locked';
  if not found then raise exception 'The annual department budget is no longer open' using errcode = '22023'; end if;
  select * into task from public.tasks where id = allocation.task_id;
  if not found then raise exception 'The funded task no longer exists' using errcode = 'P0002'; end if;
  if caller is null or not (
    task.assigned_to = caller
    or task.recommendation_lead_id = caller
    or coalesce(task.team_member_ids, '{}'::uuid[]) @> array[caller]
    or exists (
      select 1 from public.subtasks s
      where s.id = allocation.subtask_id
        and coalesce(s.assigned_to_ids, '{}'::uuid[]) @> array[caller]
    )
  ) then raise exception 'You are not assigned to this work item' using errcode = '42501'; end if;
  if p_amount <= 0 or p_amount > budget.petty_cash_request_limit then
    raise exception 'A petty-cash request cannot exceed %', to_char(budget.petty_cash_request_limit, 'FM999G999G999G990D00') using errcode = '22023';
  end if;
  if nullif(btrim(p_purpose), '') is null then raise exception 'Explain what the petty cash will be used for' using errcode = '22023'; end if;
  select coalesce(sum(case when status = 'settled' then actual_spent else approved_amount end), 0) into used
  from public.petty_cash_requests where fiscal_budget_id = budget.id
    and status in ('approved', 'liquidation_submitted', 'changes_requested', 'settled');
  if used + p_amount > budget.petty_cash_limit then raise exception 'The department petty-cash limit does not have enough remaining funds' using errcode = '22023'; end if;
  select coalesce(sum(case when status = 'settled' then actual_spent else approved_amount end), 0) into allocated_used
  from public.petty_cash_requests where allocation_id = allocation.id
    and status in ('approved', 'liquidation_submitted', 'changes_requested', 'settled');
  if allocated_used + p_amount > allocation.amount then raise exception 'This work allocation does not have enough remaining funds' using errcode = '22023'; end if;
  insert into public.petty_cash_requests(
    fiscal_budget_id, commitment_id, allocation_id, org_id, task_id, subtask_id,
    requester_id, purpose, requested_amount, needed_by
  ) values (
    budget.id, commitment.id, allocation.id, budget.org_id, allocation.task_id, allocation.subtask_id,
    caller, btrim(p_purpose), p_amount, p_needed_by
  ) returning id into request_id;
  insert into public.notifications(user_id, type, title, message, task_id, task_title, actor_id, actor_name)
  select approver_id, 'petty_cash_request', 'Petty-cash request awaiting approval',
    coalesce(p.full_name, 'An employee') || ' requested ' || to_char(p_amount, 'FM999G999G999G990D00') || ' for "' || task.title || '".',
    task.id, task.title, caller, coalesce(p.full_name, '')
  from public.organization_approver_ids(task.org_id) approver_id
  left join public.profiles p on p.id = caller
  where approver_id <> caller;
  return request_id;
end;
$$;

create or replace function public.decide_petty_cash_request(
  p_request_id uuid,
  p_approve boolean,
  p_reason text
) returns void language plpgsql security definer set search_path = public as $$
declare caller uuid := auth.uid(); request public.petty_cash_requests; budget public.department_fiscal_budgets; allocation public.work_budget_allocations; used numeric; allocation_used numeric;
begin
  select * into request from public.petty_cash_requests where id = p_request_id for update;
  if not found then raise exception 'Petty-cash request not found' using errcode = 'P0002'; end if;
  if not public.is_department_budget_approver(request.org_id, caller) then raise exception 'Only the Head or Assistant Head can decide this request' using errcode = '42501'; end if;
  if caller = request.requester_id then raise exception 'You cannot approve your own request' using errcode = '42501'; end if;
  if request.status <> 'pending' then raise exception 'This request has already been decided' using errcode = '22023'; end if;
  if not p_approve and nullif(btrim(p_reason), '') is null then raise exception 'A reason is required when declining' using errcode = '22023'; end if;
  if p_approve then
    select * into budget from public.department_fiscal_budgets
    where id = request.fiscal_budget_id and status = 'locked' for update;
    if not found then raise exception 'The annual department budget is no longer open' using errcode = '22023'; end if;
    select * into allocation from public.work_budget_allocations
    where id = request.allocation_id and status = 'approved' for update;
    if not found then raise exception 'The work allocation is no longer available' using errcode = '22023'; end if;
    select coalesce(sum(case when status = 'settled' then actual_spent else approved_amount end), 0) into used
      from public.petty_cash_requests where fiscal_budget_id = budget.id and id <> request.id
        and status in ('approved', 'liquidation_submitted', 'changes_requested', 'settled');
    select coalesce(sum(case when status = 'settled' then actual_spent else approved_amount end), 0) into allocation_used
      from public.petty_cash_requests where allocation_id = allocation.id and id <> request.id
        and status in ('approved', 'liquidation_submitted', 'changes_requested', 'settled');
    if used + request.requested_amount > budget.petty_cash_limit then raise exception 'The department petty-cash limit is no longer sufficient' using errcode = '22023'; end if;
    if allocation_used + request.requested_amount > allocation.amount then raise exception 'The work allocation is no longer sufficient' using errcode = '22023'; end if;
  end if;
  update public.petty_cash_requests set
    status = case when p_approve then 'approved' else 'rejected' end,
    approved_amount = case when p_approve then requested_amount end,
    approved_by = caller, approval_reason = nullif(btrim(p_reason), ''), decided_at = now(), updated_at = now()
  where id = request.id;
  if p_approve then
    insert into public.budget_ledger_entries(fiscal_budget_id, org_id, commitment_id, allocation_id, petty_cash_request_id, entry_type, amount, description, actor_id)
    values (request.fiscal_budget_id, request.org_id, request.commitment_id, request.allocation_id, request.id,
      'petty_cash_reserved', request.requested_amount, 'Petty cash reserved for approved request', caller);
  end if;
  insert into public.notifications(user_id, type, title, message, task_id, actor_id, actor_name, reason)
  select request.requester_id, 'petty_cash_decision', case when p_approve then 'Petty cash approved' else 'Petty cash declined' end,
    'Your petty-cash request for ' || to_char(request.requested_amount, 'FM999G999G999G990D00') || ' was ' || case when p_approve then 'approved.' else 'declined.' end,
    request.task_id, caller, coalesce(full_name, ''), coalesce(p_reason, '') from public.profiles where id = caller;
end;
$$;

create or replace function public.submit_petty_cash_liquidation(
  p_request_id uuid,
  p_declared_spent numeric,
  p_note text,
  p_receipts jsonb
) returns uuid language plpgsql security definer set search_path = public as $$
declare caller uuid := auth.uid(); request public.petty_cash_requests; item jsonb; receipt_total numeric := 0; liquidation_id uuid; next_version int;
begin
  select * into request from public.petty_cash_requests where id = p_request_id for update;
  if not found then raise exception 'Petty-cash request not found' using errcode = 'P0002'; end if;
  if request.requester_id <> caller then raise exception 'Only the requester can submit this liquidation' using errcode = '42501'; end if;
  if request.status not in ('approved', 'changes_requested') then raise exception 'This request is not ready for liquidation' using errcode = '22023'; end if;
  if p_declared_spent < 0 or p_declared_spent > request.approved_amount then raise exception 'Actual spending cannot exceed the approved amount' using errcode = '22023'; end if;
  if nullif(btrim(p_note), '') is null then raise exception 'Add a liquidation note' using errcode = '22023'; end if;
  if jsonb_typeof(coalesce(p_receipts, '[]'::jsonb)) <> 'array' or jsonb_array_length(coalesce(p_receipts, '[]'::jsonb)) = 0 then
    raise exception 'Attach at least one receipt' using errcode = '22023';
  end if;
  for item in select value from jsonb_array_elements(p_receipts) loop
    if nullif(btrim(item ->> 'vendor'), '') is null or nullif(btrim(item ->> 'description'), '') is null
       or nullif(btrim(item ->> 'filePath'), '') is null or nullif(item ->> 'receiptDate', '') is null then
      raise exception 'Every receipt needs vendor, date, description, amount, and attachment' using errcode = '22023';
    end if;
    receipt_total := receipt_total + coalesce((item ->> 'amount')::numeric, 0);
  end loop;
  if abs(receipt_total - p_declared_spent) > 0.009 then raise exception 'Receipt amounts must equal the declared amount spent' using errcode = '22023'; end if;
  select coalesce(max(version), 0) + 1 into next_version from public.petty_cash_liquidations where request_id = request.id;
  insert into public.petty_cash_liquidations(request_id, version, declared_spent, returned_amount, note, submitted_by)
  values (request.id, next_version, p_declared_spent, request.approved_amount - p_declared_spent, btrim(p_note), caller)
  returning id into liquidation_id;
  for item in select value from jsonb_array_elements(p_receipts) loop
    insert into public.petty_cash_receipts(
      liquidation_id, vendor, receipt_number, receipt_date, description, amount,
      file_name, file_path, mime_type, file_size, created_by
    ) values (
      liquidation_id, btrim(item ->> 'vendor'), nullif(btrim(item ->> 'receiptNumber'), ''),
      (item ->> 'receiptDate')::date, btrim(item ->> 'description'), (item ->> 'amount')::numeric,
      item ->> 'fileName', item ->> 'filePath', coalesce(nullif(item ->> 'mimeType', ''), 'application/octet-stream'),
      coalesce((item ->> 'fileSize')::bigint, 0), caller
    );
  end loop;
  update public.petty_cash_requests set status = 'liquidation_submitted', updated_at = now() where id = request.id;
  insert into public.notifications(user_id, type, title, message, task_id, actor_id, actor_name)
  select approver_id, 'petty_cash_liquidation', 'Petty-cash receipts ready for review',
    coalesce(p.full_name, 'An employee') || ' submitted receipts totaling ' || to_char(p_declared_spent, 'FM999G999G999G990D00') || '.',
    request.task_id, caller, coalesce(p.full_name, '')
  from public.organization_approver_ids(request.org_id) approver_id
  left join public.profiles p on p.id = caller
  where approver_id <> caller;
  return liquidation_id;
end;
$$;

create or replace function public.decide_petty_cash_liquidation(
  p_liquidation_id uuid,
  p_approve boolean,
  p_reason text
) returns void language plpgsql security definer set search_path = public as $$
declare caller uuid := auth.uid(); liquidation public.petty_cash_liquidations; request public.petty_cash_requests;
begin
  select * into liquidation from public.petty_cash_liquidations where id = p_liquidation_id for update;
  if not found then raise exception 'Liquidation not found' using errcode = 'P0002'; end if;
  select * into request from public.petty_cash_requests where id = liquidation.request_id for update;
  if not public.is_department_budget_approver(request.org_id, caller) then raise exception 'Only the Head or Assistant Head can verify this liquidation' using errcode = '42501'; end if;
  if caller = request.requester_id then raise exception 'You cannot verify your own liquidation' using errcode = '42501'; end if;
  if liquidation.status <> 'pending' or request.status <> 'liquidation_submitted' then raise exception 'This liquidation has already been decided' using errcode = '22023'; end if;
  if not p_approve and nullif(btrim(p_reason), '') is null then raise exception 'Explain what must be corrected' using errcode = '22023'; end if;
  update public.petty_cash_liquidations set status = case when p_approve then 'approved' else 'changes_requested' end,
    decided_by = caller, decision_reason = nullif(btrim(p_reason), ''), decided_at = now()
  where id = liquidation.id;
  if p_approve then
    update public.petty_cash_requests set status = 'settled', actual_spent = liquidation.declared_spent,
      returned_amount = liquidation.returned_amount, settled_by = caller, settled_at = now(), updated_at = now()
    where id = request.id;
    insert into public.budget_ledger_entries(fiscal_budget_id, org_id, commitment_id, allocation_id, petty_cash_request_id, entry_type, amount, description, actor_id)
    values (request.fiscal_budget_id, request.org_id, request.commitment_id, request.allocation_id, request.id,
      'expense_posted', liquidation.declared_spent, 'Verified petty-cash receipts posted as actual spending', caller);
    if liquidation.returned_amount > 0 then
      insert into public.budget_ledger_entries(fiscal_budget_id, org_id, commitment_id, allocation_id, petty_cash_request_id, entry_type, amount, description, actor_id)
      values (request.fiscal_budget_id, request.org_id, request.commitment_id, request.allocation_id, request.id,
        'cash_returned', liquidation.returned_amount, 'Unused petty cash returned to the work allocation', caller);
    end if;
  else
    update public.petty_cash_requests set status = 'changes_requested', updated_at = now() where id = request.id;
  end if;
  insert into public.notifications(user_id, type, title, message, task_id, actor_id, actor_name, reason)
  select request.requester_id, 'petty_cash_liquidation_decision', case when p_approve then 'Expense liquidation approved' else 'Liquidation changes requested' end,
    case when p_approve then 'Your receipts were verified and the expense was posted.' else 'Your liquidation needs corrections before it can be settled.' end,
    request.task_id, caller, coalesce(full_name, ''), coalesce(p_reason, '') from public.profiles where id = caller;
end;
$$;

create or replace function public.department_budget_summary(p_org_id uuid, p_fiscal_year int)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare budget public.department_fiscal_budgets; committed numeric := 0; spent numeric := 0; petty_reserved numeric := 0; petty_spent numeric := 0;
begin
  if auth.uid() is null or not public.can_view_department_budget(p_org_id, auth.uid()) then raise exception 'Budget access denied' using errcode = '42501'; end if;
  select * into budget from public.department_fiscal_budgets where org_id = p_org_id and fiscal_year = p_fiscal_year;
  if not found then return null; end if;
  select coalesce(sum(amount), 0) into committed from public.budget_commitments where fiscal_budget_id = budget.id and status = 'active';
  select coalesce(sum(actual_spent), 0) into spent from public.petty_cash_requests where fiscal_budget_id = budget.id and status = 'settled';
  select coalesce(sum(approved_amount), 0) into petty_reserved from public.petty_cash_requests
    where fiscal_budget_id = budget.id and status in ('approved', 'liquidation_submitted', 'changes_requested');
  petty_spent := spent;
  return jsonb_build_object(
    'id', budget.id, 'orgId', budget.org_id, 'fiscalYear', budget.fiscal_year, 'status', budget.status,
    'approvedAmount', budget.approved_amount, 'committedAmount', committed, 'spentAmount', spent,
    'availableAmount', greatest(0, budget.approved_amount - committed),
    'commitmentRemaining', greatest(0, committed - spent),
    'pettyCashLimit', budget.petty_cash_limit, 'pettyCashRequestLimit', budget.petty_cash_request_limit,
    'pettyCashReserved', petty_reserved, 'pettyCashSpent', petty_spent,
    'pettyCashAvailable', greatest(0, budget.petty_cash_limit - petty_reserved - petty_spent),
    'underutilizationThreshold', budget.underutilization_threshold, 'notes', budget.notes,
    'lockedAt', budget.locked_at, 'updatedAt', budget.updated_at
  );
end;
$$;

alter table public.department_fiscal_budgets enable row level security;
alter table public.department_budget_lines enable row level security;
alter table public.budget_commitments enable row level security;
alter table public.work_budget_allocations enable row level security;
alter table public.petty_cash_requests enable row level security;
alter table public.petty_cash_liquidations enable row level security;
alter table public.petty_cash_receipts enable row level security;
alter table public.budget_ledger_entries enable row level security;

create policy department_fiscal_budgets_read on public.department_fiscal_budgets for select to authenticated
using (public.can_view_department_budget(org_id, auth.uid()));
create policy department_budget_lines_read on public.department_budget_lines for select to authenticated
using (exists (select 1 from public.department_fiscal_budgets b where b.id = fiscal_budget_id and public.can_view_department_budget(b.org_id, auth.uid())));
create policy budget_commitments_read on public.budget_commitments for select to authenticated
using (exists (select 1 from public.department_fiscal_budgets b where b.id = fiscal_budget_id and public.can_view_department_budget(b.org_id, auth.uid())));
create policy work_budget_allocations_read on public.work_budget_allocations for select to authenticated
using (public.can_see_task(task_id, auth.uid()));
create policy petty_cash_requests_read on public.petty_cash_requests for select to authenticated
using (requester_id = auth.uid() or public.is_department_budget_approver(org_id, auth.uid()));
create policy petty_cash_liquidations_read on public.petty_cash_liquidations for select to authenticated
using (exists (select 1 from public.petty_cash_requests r where r.id = request_id and (r.requester_id = auth.uid() or public.is_department_budget_approver(r.org_id, auth.uid()))));
create policy petty_cash_receipts_read on public.petty_cash_receipts for select to authenticated
using (exists (
  select 1 from public.petty_cash_liquidations l join public.petty_cash_requests r on r.id = l.request_id
  where l.id = liquidation_id and (r.requester_id = auth.uid() or public.is_department_budget_approver(r.org_id, auth.uid()))
));
create policy budget_ledger_entries_read on public.budget_ledger_entries for select to authenticated
using (public.is_department_budget_approver(org_id, auth.uid()));

insert into storage.buckets(id, name, public, file_size_limit, allowed_mime_types)
values ('budget-receipts', 'budget-receipts', false, 10485760, array['image/jpeg','image/png','image/webp','application/pdf'])
on conflict (id) do update set public = false, file_size_limit = excluded.file_size_limit, allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists budget_receipts_insert on storage.objects;
create policy budget_receipts_insert on storage.objects for insert to authenticated
with check (bucket_id = 'budget-receipts' and public.can_view_department_budget((storage.foldername(name))[1]::uuid, auth.uid()));
drop policy if exists budget_receipts_read on storage.objects;
create policy budget_receipts_read on storage.objects for select to authenticated
using (bucket_id = 'budget-receipts' and public.can_view_department_budget((storage.foldername(name))[1]::uuid, auth.uid()));
drop policy if exists budget_receipts_delete on storage.objects;
create policy budget_receipts_delete on storage.objects for delete to authenticated
using (bucket_id = 'budget-receipts' and owner_id = auth.uid()::text);

revoke all on public.department_fiscal_budgets, public.department_budget_lines, public.budget_commitments,
  public.work_budget_allocations, public.petty_cash_requests, public.petty_cash_liquidations,
  public.petty_cash_receipts, public.budget_ledger_entries from anon;
grant select on public.department_fiscal_budgets, public.department_budget_lines, public.budget_commitments,
  public.work_budget_allocations, public.petty_cash_requests, public.petty_cash_liquidations,
  public.petty_cash_receipts, public.budget_ledger_entries to authenticated;
grant execute on function public.save_department_fiscal_budget(uuid,int,numeric,numeric,numeric,text,jsonb) to authenticated;
grant execute on function public.lock_department_fiscal_budget(uuid) to authenticated;
grant execute on function public.create_work_budget_allocation(uuid,uuid,numeric,text) to authenticated;
grant execute on function public.decide_work_budget_allocation(uuid,boolean,text) to authenticated;
grant execute on function public.create_petty_cash_request(uuid,numeric,text,date) to authenticated;
grant execute on function public.decide_petty_cash_request(uuid,boolean,text) to authenticated;
grant execute on function public.submit_petty_cash_liquidation(uuid,numeric,text,jsonb) to authenticated;
grant execute on function public.decide_petty_cash_liquidation(uuid,boolean,text) to authenticated;
grant execute on function public.department_budget_summary(uuid,int) to authenticated;
grant execute on function public.can_view_department_budget(uuid,uuid) to authenticated;

do $$
declare tbl text;
begin
  foreach tbl in array array[
    'department_fiscal_budgets','department_budget_lines','budget_commitments',
    'work_budget_allocations','petty_cash_requests','petty_cash_liquidations',
    'petty_cash_receipts','budget_ledger_entries'
  ] loop
    begin execute format('alter publication supabase_realtime add table public.%I', tbl);
    exception when duplicate_object then null; when undefined_object then null;
    end;
  end loop;
end;
$$;

notify pgrst, 'reload schema';
