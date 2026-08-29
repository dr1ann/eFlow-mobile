-- Drop the old policy that recursively called public.can_see_project
drop policy if exists "projects readable in scope" on public.projects;

-- Recreate the policy with direct column references to avoid recursion and SELECT-during-INSERT failures
create policy "projects readable in scope" on public.projects for select to authenticated
  using (
    public.is_super_admin(auth.uid())
    or owner_id = auth.uid()
    or public.org_in_my_subtree(org_id, auth.uid())
    or public.is_project_member(id, auth.uid())
  );
