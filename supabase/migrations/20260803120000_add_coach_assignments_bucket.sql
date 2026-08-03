-- Private bucket for custom-goal coach-assignment photos ("the original
-- stays attached -- your coach sees exactly what you trained against",
-- spec: docs/features/sport-skill-programs.md, "Custom goals"). Follows
-- the body-photos archetype exactly: private bucket, user-scoped path RLS
-- ({auth.uid()}/...), no public read anywhere.

insert into storage.buckets (id, name, public)
values ('coach-assignments', 'coach-assignments', false)
on conflict (id) do nothing;

-- BUG-23 guard: a bare CREATE POLICY on storage.objects aborts the whole
-- push chain when the role lacks table ownership (hosted `db push`).
do $$
begin
  create policy "coach_assignments_select_own" on storage.objects
    for select using (bucket_id = 'coach-assignments' and (storage.foldername(name))[1] = auth.uid()::text);

  create policy "coach_assignments_insert_own" on storage.objects
    for insert with check (bucket_id = 'coach-assignments' and (storage.foldername(name))[1] = auth.uid()::text);

  create policy "coach_assignments_update_own" on storage.objects
    for update using (bucket_id = 'coach-assignments' and (storage.foldername(name))[1] = auth.uid()::text);

  create policy "coach_assignments_delete_own" on storage.objects
    for delete using (bucket_id = 'coach-assignments' and (storage.foldername(name))[1] = auth.uid()::text);
exception
  when insufficient_privilege then
    raise notice 'Skipped coach-assignments storage policies (role lacks storage.objects ownership) -- create them via Dashboard -> Storage -> coach-assignments -> Policies.';
  when duplicate_object then
    null;
end $$;
