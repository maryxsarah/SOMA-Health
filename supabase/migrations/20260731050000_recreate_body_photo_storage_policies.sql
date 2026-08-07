-- The original body-photos storage policies (20260729010000) were created
-- inside a guarded block that silently skips on insufficient_privilege --
-- necessary so a missing privilege doesn't break the whole migration
-- chain, but it also means a silent skip looks identical to success, with
-- no way to tell from the migration history alone whether the policies
-- actually exist. "Remove photo" failing in the app (a DELETE against
-- storage.objects that RLS quietly rejects) is exactly the symptom a
-- missing delete policy would produce. Re-running drop-then-create here
-- is idempotent either way: harmless if the policies already existed,
-- self-healing if they didn't.
do $$
begin
  drop policy if exists "body_photos_select_own" on storage.objects;
  drop policy if exists "body_photos_insert_own" on storage.objects;
  drop policy if exists "body_photos_update_own" on storage.objects;
  drop policy if exists "body_photos_delete_own" on storage.objects;

  create policy "body_photos_select_own" on storage.objects
    for select using (bucket_id = 'body-photos' and (storage.foldername(name))[1] = auth.uid()::text);

  create policy "body_photos_insert_own" on storage.objects
    for insert with check (bucket_id = 'body-photos' and (storage.foldername(name))[1] = auth.uid()::text);

  create policy "body_photos_update_own" on storage.objects
    for update using (bucket_id = 'body-photos' and (storage.foldername(name))[1] = auth.uid()::text);

  create policy "body_photos_delete_own" on storage.objects
    for delete using (bucket_id = 'body-photos' and (storage.foldername(name))[1] = auth.uid()::text);

  raise notice 'body-photos storage policies recreated successfully.';
exception
  when insufficient_privilege then
    raise notice 'Could not recreate body-photos storage policies (role lacks storage.objects ownership) -- create the 4 policies manually via Dashboard -> Storage -> body-photos -> Policies: select/insert/update/delete, each scoped to bucket_id = ''body-photos'' and (storage.foldername(name))[1] = auth.uid()::text.';
end $$;
