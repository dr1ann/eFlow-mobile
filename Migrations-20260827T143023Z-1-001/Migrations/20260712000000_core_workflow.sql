-- ─────────────────────────────────────────────────────────────────────────────
-- Core Workflow & Roles foundation (Phase 0)
--
-- Adds the shared operational data model that Department Head, Super Admin, and
-- Employee screens all read from:
--   projects, project_members, milestones,
--   task_progress_updates, task_comments, task_comment_attachments,
--   announcements, announcement_recipients,
--   audit_events,
--   role_permissions, user_permission_overrides
--
-- Plus new task columns, RLS policies scoped to the org subtree, indexes for the
-- common queries, a seeded permission matrix, and a private storage bucket for
-- comment attachments.
--
-- Idempotent — safe to run repeatedly. Apply through the project's normal
-- Supabase migration workflow. Naming note: `tasks.project_id` already exists and
-- refers to the proposal-decomposition hierarchy. The NEW operational link is
-- `tasks.linked_project_id`, so the two never collide.
-- ─────────────────────────────────────────────────────────────────────────────

-- ═══ Scope helper functions ══════════════════════════════════════════════════
-- security definer so they can read profiles/organizations regardless of the
-- caller's RLS. Used by the policies below. Querying profiles/organizations from
-- policies on OTHER tables does not recurse.

create or replace function public.auth_role(caller_id uuid)
returns text language plpgsql stable security definer set search_path = public as $$
begin
  return (select role::text from public.profiles where id = caller_id);
end;
$$;

create or replace function public.auth_org_path(caller_id uuid)
returns text language plpgsql stable security definer set search_path = public as $$
begin
  return (
    select o.path::text
    from public.organizations o
    join public.profiles p on p.org_id = o.id
    where p.id = caller_id
  );
end;
$$;

-- Is target_org the caller's own org or a descendant of it? (ltree/text safe.)
create or replace function public.org_in_my_subtree(target_org uuid, caller_id uuid)
returns boolean language plpgsql stable security definer set search_path = public as $$
declare
  caller_path text;
begin
  caller_path := public.auth_org_path(caller_id);
  if caller_path is null then
    return false;
  end if;
  return exists (
    select 1
    from public.organizations o
    where o.id = target_org
      and (o.path::text = caller_path or o.path::text like caller_path || '.%')
  );
end;
$$;

create or replace function public.is_super_admin(caller_id uuid)
returns boolean language plpgsql stable security definer set search_path = public as $$
begin
  return public.auth_role(caller_id) = 'super_admin';
end;
$$;

-- Generic updated_at touch trigger reused by every table below.
create or replace function public.touch_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

-- ═══ projects ════════════════════════════════════════════════════════════════
create table if not exists public.projects (
  id           uuid primary key default gen_random_uuid(),
  org_id       uuid references public.organizations(id) on delete set null,
  title        text not null,
  description  text not null default '',
  owner_id     uuid references public.profiles(id) on delete set null,
  status       text not null default 'planning'
                 check (status in ('planning','active','on_hold','completed','archived')),
  priority     text not null default 'medium'
                 check (priority in ('low','medium','high')),
  start_date   date,
  target_date  date,
  archived_at  timestamptz,
  created_by   uuid references public.profiles(id) on delete set null,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);

create index if not exists projects_org_idx        on public.projects(org_id);
create index if not exists projects_status_idx     on public.projects(status);
create index if not exists projects_target_idx     on public.projects(target_date);
create index if not exists projects_owner_idx      on public.projects(owner_id);

drop trigger if exists projects_touch on public.projects;
create trigger projects_touch before update on public.projects
  for each row execute function public.touch_updated_at();

-- ═══ project_members ═════════════════════════════════════════════════════════
create table if not exists public.project_members (
  project_id uuid not null references public.projects(id) on delete cascade,
  user_id    uuid not null references public.profiles(id) on delete cascade,
  role       text not null default 'member' check (role in ('owner','member','viewer')),
  created_at timestamptz not null default now(),
  primary key (project_id, user_id)
);

create index if not exists project_members_user_idx on public.project_members(user_id);

-- Am I a member of this project?
create or replace function public.is_project_member(target_project uuid, caller_id uuid)
returns boolean language plpgsql stable security definer set search_path = public as $$
begin
  return exists (
    select 1 from public.project_members m
    where m.project_id = target_project and m.user_id = caller_id
  );
end;
$$;

-- Can I see this project? super admin, in-subtree, owner, or member.
create or replace function public.can_see_project(target_project uuid, caller_id uuid)
returns boolean language plpgsql stable security definer set search_path = public as $$
declare
  proj_org uuid;
  proj_owner uuid;
begin
  if public.is_super_admin(caller_id) then
    return true;
  end if;

  select org_id, owner_id into proj_org, proj_owner
  from public.projects
  where id = target_project;

  if not found then
    return false;
  end if;

  return (
    proj_owner = caller_id
    or public.org_in_my_subtree(proj_org, caller_id)
    or public.is_project_member(target_project, caller_id)
  );
end;
$$;

-- ═══ milestones ══════════════════════════════════════════════════════════════
create table if not exists public.milestones (
  id             uuid primary key default gen_random_uuid(),
  project_id     uuid not null references public.projects(id) on delete cascade,
  title          text not null,
  description    text not null default '',
  due_date       date,
  status         text not null default 'auto'
                   check (status in ('auto','not_started','in_progress','at_risk','completed')),
  manual_status  text check (manual_status in ('not_started','in_progress','at_risk','completed')),
  manual_note    text,
  sort_order     int not null default 0,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now()
);

create index if not exists milestones_project_idx on public.milestones(project_id, sort_order);

drop trigger if exists milestones_touch on public.milestones;
create trigger milestones_touch before update on public.milestones
  for each row execute function public.touch_updated_at();

-- ═══ tasks: new operational columns ══════════════════════════════════════════
alter table public.tasks add column if not exists linked_project_id uuid references public.projects(id) on delete set null;
alter table public.tasks add column if not exists milestone_id      uuid references public.milestones(id) on delete set null;
alter table public.tasks add column if not exists percent_complete  int not null default 0 check (percent_complete between 0 and 100);
alter table public.tasks add column if not exists archived_at       timestamptz;
alter table public.tasks add column if not exists last_activity_at  timestamptz;

create index if not exists tasks_linked_project_idx on public.tasks(linked_project_id);
create index if not exists tasks_milestone_idx      on public.tasks(milestone_id);
create index if not exists tasks_status_idx         on public.tasks(status);
create index if not exists tasks_assignee_idx       on public.tasks(assigned_to);
create index if not exists tasks_org_idx            on public.tasks(org_id);
-- Review queue: partial index over just the for_review rows.
create index if not exists tasks_review_queue_idx   on public.tasks(status) where status = 'for_review';

-- ═══ task_progress_updates ═══════════════════════════════════════════════════
create table if not exists public.task_progress_updates (
  id               uuid primary key default gen_random_uuid(),
  task_id          uuid not null references public.tasks(id) on delete cascade,
  author_id        uuid references public.profiles(id) on delete set null,
  author_name      text not null default '',
  percent_complete int check (percent_complete between 0 and 100),
  blocker_category text,
  blocker          text,
  next_step        text,
  note             text,
  attachment_path  text,
  attachment_name  text,
  created_at       timestamptz not null default now()
);

create index if not exists task_progress_task_idx on public.task_progress_updates(task_id, created_at desc);

-- ═══ task_comments ═══════════════════════════════════════════════════════════
create table if not exists public.task_comments (
  id          uuid primary key default gen_random_uuid(),
  task_id     uuid not null references public.tasks(id) on delete cascade,
  author_id   uuid references public.profiles(id) on delete set null,
  author_name text not null default '',
  body        text not null,
  created_at  timestamptz not null default now(),
  edited_at   timestamptz,
  deleted_at  timestamptz,
  deleted_by  uuid references public.profiles(id) on delete set null
);

create index if not exists task_comments_task_idx on public.task_comments(task_id, created_at);

-- ═══ task_comment_attachments ════════════════════════════════════════════════
create table if not exists public.task_comment_attachments (
  id            uuid primary key default gen_random_uuid(),
  comment_id    uuid not null references public.task_comments(id) on delete cascade,
  storage_path  text not null,
  file_name     text not null default '',
  mime_type     text not null default '',
  file_size     bigint not null default 0,
  created_at    timestamptz not null default now()
);

create index if not exists task_comment_attach_idx on public.task_comment_attachments(comment_id);

-- ═══ announcements ═══════════════════════════════════════════════════════════
create table if not exists public.announcements (
  id           uuid primary key default gen_random_uuid(),
  title        text not null,
  body         text not null default '',
  audience     text not null default 'all' check (audience in ('all','org','users')),
  org_id       uuid references public.organizations(id) on delete set null,
  status       text not null default 'draft' check (status in ('draft','published','withdrawn')),
  published_at timestamptz,
  expires_at   timestamptz,
  created_by   uuid references public.profiles(id) on delete set null,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);

create index if not exists announcements_status_idx on public.announcements(status, published_at desc);

drop trigger if exists announcements_touch on public.announcements;
create trigger announcements_touch before update on public.announcements
  for each row execute function public.touch_updated_at();

-- ═══ announcement_recipients ═════════════════════════════════════════════════
create table if not exists public.announcement_recipients (
  announcement_id uuid not null references public.announcements(id) on delete cascade,
  user_id         uuid not null references public.profiles(id) on delete cascade,
  read_at         timestamptz,
  created_at      timestamptz not null default now(),
  primary key (announcement_id, user_id)
);

create index if not exists announcement_recipients_user_idx on public.announcement_recipients(user_id, read_at);

-- ═══ audit_events (append-only) ══════════════════════════════════════════════
create table if not exists public.audit_events (
  id          uuid primary key default gen_random_uuid(),
  actor_id    uuid references public.profiles(id) on delete set null,
  actor_name  text not null default '',
  entity_type text not null,
  entity_id   text,
  action      text not null,
  reason      text,
  before_data jsonb,
  after_data  jsonb,
  metadata    jsonb,
  org_id      uuid references public.organizations(id) on delete set null,
  created_at  timestamptz not null default now()
);

create index if not exists audit_entity_idx on public.audit_events(entity_type, entity_id, created_at desc);
create index if not exists audit_actor_idx  on public.audit_events(actor_id, created_at desc);
create index if not exists audit_action_idx on public.audit_events(action, created_at desc);
create index if not exists audit_org_idx    on public.audit_events(org_id, created_at desc);

-- ═══ role_permissions + user_permission_overrides ════════════════════════════
create table if not exists public.role_permissions (
  role       text not null,
  permission text not null,
  allowed    boolean not null default false,
  updated_at timestamptz not null default now(),
  primary key (role, permission)
);

create table if not exists public.user_permission_overrides (
  user_id    uuid not null references public.profiles(id) on delete cascade,
  permission text not null,
  allowed    boolean not null,
  set_by     uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  primary key (user_id, permission)
);

-- Seed the default capability matrix. ON CONFLICT DO NOTHING keeps any
-- admin-tuned values on re-run.
insert into public.role_permissions (role, permission, allowed) values
  ('super_admin','projects.create',true),
  ('super_admin','projects.archive',true),
  ('super_admin','tasks.assign',true),
  ('super_admin','tasks.verify',true),
  ('super_admin','reports.export',true),
  ('super_admin','announcements.publish',true),
  ('super_admin','users.manage',true),
  ('super_admin','audit.read',true),
  ('super_admin','settings.manage',true),
  ('dept_head','projects.create',true),
  ('dept_head','projects.archive',true),
  ('dept_head','tasks.assign',true),
  ('dept_head','tasks.verify',true),
  ('dept_head','reports.export',true),
  ('dept_head','announcements.publish',false),
  ('dept_head','users.manage',false),
  ('dept_head','audit.read',false),
  ('dept_head','settings.manage',false),
  ('employee','projects.create',false),
  ('employee','projects.archive',false),
  ('employee','tasks.assign',false),
  ('employee','tasks.verify',false),
  ('employee','reports.export',true),
  ('employee','announcements.publish',false),
  ('employee','users.manage',false),
  ('employee','audit.read',false),
  ('employee','settings.manage',false)
on conflict (role, permission) do nothing;

-- ═══ Row Level Security ══════════════════════════════════════════════════════
alter table public.projects                  enable row level security;
alter table public.project_members           enable row level security;
alter table public.milestones                enable row level security;
alter table public.task_progress_updates     enable row level security;
alter table public.task_comments             enable row level security;
alter table public.task_comment_attachments  enable row level security;
alter table public.announcements             enable row level security;
alter table public.announcement_recipients   enable row level security;
alter table public.audit_events              enable row level security;
alter table public.role_permissions          enable row level security;
alter table public.user_permission_overrides enable row level security;

do $$
begin
  -- ── projects ──────────────────────────────────────────────────────────────
  if not exists (select 1 from pg_policies where schemaname='public' and tablename='projects' and policyname='projects readable in scope') then
    create policy "projects readable in scope" on public.projects for select to authenticated
      using (public.can_see_project(id, auth.uid()));
  end if;
  if not exists (select 1 from pg_policies where schemaname='public' and tablename='projects' and policyname='projects writable in subtree') then
    create policy "projects writable in subtree" on public.projects for insert to authenticated
      with check (public.is_super_admin(auth.uid()) or public.org_in_my_subtree(org_id, auth.uid()));
  end if;
  if not exists (select 1 from pg_policies where schemaname='public' and tablename='projects' and policyname='projects updatable in subtree') then
    create policy "projects updatable in subtree" on public.projects for update to authenticated
      using (public.is_super_admin(auth.uid()) or public.org_in_my_subtree(org_id, auth.uid()) or owner_id = auth.uid())
      with check (public.is_super_admin(auth.uid()) or public.org_in_my_subtree(org_id, auth.uid()) or owner_id = auth.uid());
  end if;

  -- ── project_members ───────────────────────────────────────────────────────
  if not exists (select 1 from pg_policies where schemaname='public' and tablename='project_members' and policyname='members readable for visible projects') then
    create policy "members readable for visible projects" on public.project_members for select to authenticated
      using (user_id = auth.uid() or public.can_see_project(project_id, auth.uid()));
  end if;
  if not exists (select 1 from pg_policies where schemaname='public' and tablename='project_members' and policyname='members writable by managers') then
    create policy "members writable by managers" on public.project_members for all to authenticated
      using (public.is_super_admin(auth.uid()) or public.can_see_project(project_id, auth.uid()))
      with check (public.is_super_admin(auth.uid()) or public.can_see_project(project_id, auth.uid()));
  end if;

  -- ── milestones ────────────────────────────────────────────────────────────
  if not exists (select 1 from pg_policies where schemaname='public' and tablename='milestones' and policyname='milestones readable for visible projects') then
    create policy "milestones readable for visible projects" on public.milestones for select to authenticated
      using (public.can_see_project(project_id, auth.uid()));
  end if;
  if not exists (select 1 from pg_policies where schemaname='public' and tablename='milestones' and policyname='milestones writable by managers') then
    create policy "milestones writable by managers" on public.milestones for all to authenticated
      using (public.is_super_admin(auth.uid()) or public.org_in_my_subtree((select org_id from public.projects where id = project_id), auth.uid()))
      with check (public.is_super_admin(auth.uid()) or public.org_in_my_subtree((select org_id from public.projects where id = project_id), auth.uid()));
  end if;

  -- ── task_progress_updates ─────────────────────────────────────────────────
  if not exists (select 1 from pg_policies where schemaname='public' and tablename='task_progress_updates' and policyname='progress readable to authenticated') then
    create policy "progress readable to authenticated" on public.task_progress_updates for select to authenticated using (true);
  end if;
  if not exists (select 1 from pg_policies where schemaname='public' and tablename='task_progress_updates' and policyname='progress insert self') then
    create policy "progress insert self" on public.task_progress_updates for insert to authenticated
      with check (author_id = auth.uid());
  end if;

  -- ── task_comments ─────────────────────────────────────────────────────────
  if not exists (select 1 from pg_policies where schemaname='public' and tablename='task_comments' and policyname='comments readable to authenticated') then
    create policy "comments readable to authenticated" on public.task_comments for select to authenticated using (true);
  end if;
  if not exists (select 1 from pg_policies where schemaname='public' and tablename='task_comments' and policyname='comments insert self') then
    create policy "comments insert self" on public.task_comments for insert to authenticated
      with check (author_id = auth.uid());
  end if;
  -- Author edits their own; managers/super-admin may soft-delete (moderation).
  if not exists (select 1 from pg_policies where schemaname='public' and tablename='task_comments' and policyname='comments update author or moderator') then
    create policy "comments update author or moderator" on public.task_comments for update to authenticated
      using (author_id = auth.uid() or public.is_super_admin(auth.uid()) or public.auth_role(auth.uid()) = 'dept_head')
      with check (author_id = auth.uid() or public.is_super_admin(auth.uid()) or public.auth_role(auth.uid()) = 'dept_head');
  end if;

  -- ── task_comment_attachments ──────────────────────────────────────────────
  if not exists (select 1 from pg_policies where schemaname='public' and tablename='task_comment_attachments' and policyname='comment attachments readable') then
    create policy "comment attachments readable" on public.task_comment_attachments for select to authenticated using (true);
  end if;
  if not exists (select 1 from pg_policies where schemaname='public' and tablename='task_comment_attachments' and policyname='comment attachments insert') then
    create policy "comment attachments insert" on public.task_comment_attachments for insert to authenticated with check (true);
  end if;

  -- ── announcements ─────────────────────────────────────────────────────────
  -- Everyone may read published, non-expired announcements they are a recipient
  -- of, plus authors/admins see their drafts.
  if not exists (select 1 from pg_policies where schemaname='public' and tablename='announcements' and policyname='announcements readable') then
    create policy "announcements readable" on public.announcements for select to authenticated
      using (
        public.is_super_admin(auth.uid())
        or created_by = auth.uid()
        or (status = 'published' and exists (
              select 1 from public.announcement_recipients r
              where r.announcement_id = id and r.user_id = auth.uid()))
      );
  end if;
  if not exists (select 1 from pg_policies where schemaname='public' and tablename='announcements' and policyname='announcements writable by publishers') then
    create policy "announcements writable by publishers" on public.announcements for all to authenticated
      using (public.is_super_admin(auth.uid()))
      with check (public.is_super_admin(auth.uid()));
  end if;

  -- ── announcement_recipients ───────────────────────────────────────────────
  if not exists (select 1 from pg_policies where schemaname='public' and tablename='announcement_recipients' and policyname='recipients read own') then
    create policy "recipients read own" on public.announcement_recipients for select to authenticated
      using (user_id = auth.uid() or public.is_super_admin(auth.uid()));
  end if;
  if not exists (select 1 from pg_policies where schemaname='public' and tablename='announcement_recipients' and policyname='recipients insert by admin') then
    create policy "recipients insert by admin" on public.announcement_recipients for insert to authenticated
      with check (public.is_super_admin(auth.uid()));
  end if;
  -- A recipient can mark their own row read.
  if not exists (select 1 from pg_policies where schemaname='public' and tablename='announcement_recipients' and policyname='recipients update own') then
    create policy "recipients update own" on public.announcement_recipients for update to authenticated
      using (user_id = auth.uid()) with check (user_id = auth.uid());
  end if;

  -- ── audit_events (append-only) ────────────────────────────────────────────
  -- Insert allowed for authenticated (actor must be self). No UPDATE/DELETE
  -- policy exists → those operations are denied for every non-service client.
  if not exists (select 1 from pg_policies where schemaname='public' and tablename='audit_events' and policyname='audit insert self') then
    create policy "audit insert self" on public.audit_events for insert to authenticated
      with check (actor_id = auth.uid() or actor_id is null);
  end if;
  if not exists (select 1 from pg_policies where schemaname='public' and tablename='audit_events' and policyname='audit readable admin or subtree') then
    create policy "audit readable admin or subtree" on public.audit_events for select to authenticated
      using (
        public.is_super_admin(auth.uid())
        or actor_id = auth.uid()
        or (org_id is not null and public.org_in_my_subtree(org_id, auth.uid()))
      );
  end if;

  -- ── role_permissions ──────────────────────────────────────────────────────
  if not exists (select 1 from pg_policies where schemaname='public' and tablename='role_permissions' and policyname='role perms readable') then
    create policy "role perms readable" on public.role_permissions for select to authenticated using (true);
  end if;
  if not exists (select 1 from pg_policies where schemaname='public' and tablename='role_permissions' and policyname='role perms writable by admin') then
    create policy "role perms writable by admin" on public.role_permissions for all to authenticated
      using (public.is_super_admin(auth.uid())) with check (public.is_super_admin(auth.uid()));
  end if;

  -- ── user_permission_overrides ─────────────────────────────────────────────
  if not exists (select 1 from pg_policies where schemaname='public' and tablename='user_permission_overrides' and policyname='overrides readable self or admin') then
    create policy "overrides readable self or admin" on public.user_permission_overrides for select to authenticated
      using (user_id = auth.uid() or public.is_super_admin(auth.uid()));
  end if;
  if not exists (select 1 from pg_policies where schemaname='public' and tablename='user_permission_overrides' and policyname='overrides writable by admin') then
    create policy "overrides writable by admin" on public.user_permission_overrides for all to authenticated
      using (public.is_super_admin(auth.uid())) with check (public.is_super_admin(auth.uid()));
  end if;
end;
$$;

-- ═══ Private storage bucket for comment attachments ══════════════════════════
insert into storage.buckets (id, name, public, file_size_limit)
values ('task-comment-attachments', 'task-comment-attachments', false, 10485760)
on conflict (id) do update set public = false, file_size_limit = excluded.file_size_limit;

drop policy if exists "comment attachment read auth" on storage.objects;
drop policy if exists "comment attachment insert auth" on storage.objects;

create policy "comment attachment read auth"
on storage.objects for select to authenticated
using (bucket_id = 'task-comment-attachments');

create policy "comment attachment insert auth"
on storage.objects for insert to authenticated
with check (bucket_id = 'task-comment-attachments');
