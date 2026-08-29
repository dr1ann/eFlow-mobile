-- Personal account settings: profile photo, appearance, notifications, and password.
-- Apply through the project's normal Supabase migration/deployment workflow.

alter table public.profiles
  add column if not exists avatar_path text;

alter table public.profiles
  add column if not exists email_notifications_enabled boolean not null default true;

create table if not exists public.user_preferences (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  theme text not null default 'system'
    check (theme in ('light', 'dark', 'system')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

insert into public.user_preferences (user_id)
select id from public.profiles
on conflict (user_id) do nothing;

create or replace function public.create_default_user_preferences()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.user_preferences (user_id)
  values (new.id)
  on conflict (user_id) do nothing;
  return new;
end;
$$;

drop trigger if exists create_default_user_preferences_after_profile_insert on public.profiles;
create trigger create_default_user_preferences_after_profile_insert
after insert on public.profiles
for each row execute function public.create_default_user_preferences();

create or replace function public.set_user_preferences_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists set_user_preferences_updated_at on public.user_preferences;
create trigger set_user_preferences_updated_at
before update on public.user_preferences
for each row execute function public.set_user_preferences_updated_at();

alter table public.user_preferences enable row level security;

do $$
begin
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'user_preferences' and policyname = 'users read own preferences') then
    create policy "users read own preferences" on public.user_preferences for select using (auth.uid() = user_id);
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'user_preferences' and policyname = 'users insert own preferences') then
    create policy "users insert own preferences" on public.user_preferences for insert with check (auth.uid() = user_id);
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'user_preferences' and policyname = 'users update own preferences') then
    create policy "users update own preferences" on public.user_preferences for update using (auth.uid() = user_id) with check (auth.uid() = user_id);
  end if;
end;
$$;

-- Allow users to change only personal settings even where an earlier version
-- of this trigger exists. Privileged server updates are unaffected because
-- auth.uid() is null for the service-role client.
create or replace function public.guard_self_profile_update()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if auth.uid() is not null and auth.uid() = old.id then
    if new.role is distinct from old.role
      or new.org_id is distinct from old.org_id
      or new.employee_id is distinct from old.employee_id
      or new.workload is distinct from old.workload
      or new.burnout_level is distinct from old.burnout_level
      or new.is_active is distinct from old.is_active then
      raise exception 'You may only update personal profile settings.' using errcode = '42501';
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists guard_self_profile_update on public.profiles;
create trigger guard_self_profile_update
before update on public.profiles
for each row execute function public.guard_self_profile_update();

-- Private owner-only bucket for signed avatar URLs.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('profile-avatars', 'profile-avatars', false, 2097152, array['image/jpeg', 'image/png', 'image/webp'])
on conflict (id) do update
set public = false,
    file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "profile avatar owners can read" on storage.objects;
drop policy if exists "profile avatar owners can insert" on storage.objects;
drop policy if exists "profile avatar owners can update" on storage.objects;
drop policy if exists "profile avatar owners can delete" on storage.objects;

create policy "profile avatar owners can read"
on storage.objects for select to authenticated
using (bucket_id = 'profile-avatars' and (storage.foldername(name))[1] = auth.uid()::text);

create policy "profile avatar owners can insert"
on storage.objects for insert to authenticated
with check (bucket_id = 'profile-avatars' and (storage.foldername(name))[1] = auth.uid()::text);

create policy "profile avatar owners can update"
on storage.objects for update to authenticated
using (bucket_id = 'profile-avatars' and (storage.foldername(name))[1] = auth.uid()::text)
with check (bucket_id = 'profile-avatars' and (storage.foldername(name))[1] = auth.uid()::text);

create policy "profile avatar owners can delete"
on storage.objects for delete to authenticated
using (bucket_id = 'profile-avatars' and (storage.foldername(name))[1] = auth.uid()::text);
