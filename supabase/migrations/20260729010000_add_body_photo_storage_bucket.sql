-- Private bucket for goal/current body photos, standard Supabase
-- private-bucket + user-scoped-path RLS pattern -- first Storage usage in
-- this codebase, so this follows Supabase's documented convention rather
-- than an existing precedent: path prefix {auth.uid()}/... gates all four
-- operations. Feature is client-side flagged off (Config.enableBodyPhotoUpload)
-- pending legal review of the storage/consent copy.

insert into storage.buckets (id, name, public)
values ('body-photos', 'body-photos', false)
on conflict (id) do nothing;

-- CREATE POLICY on storage.objects requires ownership of that table. On
-- hosted Supabase it is owned by supabase_storage_admin, and `db push`
-- runs as postgres -- a bare CREATE POLICY aborts the whole push with
-- "must be owner of table objects", taking every later migration down
-- with it. Guarded so environments where the role lacks the privilege
-- skip the policies with a notice instead of failing the chain; on such
-- projects, create these four policies once via the dashboard
-- (Storage -> body-photos -> Policies), which runs with sufficient
-- privileges. duplicate_object is swallowed for reruns after a repair.
do $$
begin
  create policy "body_photos_select_own" on storage.objects
    for select using (bucket_id = 'body-photos' and (storage.foldername(name))[1] = auth.uid()::text);

  create policy "body_photos_insert_own" on storage.objects
    for insert with check (bucket_id = 'body-photos' and (storage.foldername(name))[1] = auth.uid()::text);

  create policy "body_photos_update_own" on storage.objects
    for update using (bucket_id = 'body-photos' and (storage.foldername(name))[1] = auth.uid()::text);

  create policy "body_photos_delete_own" on storage.objects
    for delete using (bucket_id = 'body-photos' and (storage.foldername(name))[1] = auth.uid()::text);
exception
  when insufficient_privilege then
    raise notice 'Skipped body-photos storage policies (role lacks storage.objects ownership) -- create them via the dashboard.';
  when duplicate_object then
    null;
end $$;
