-- Private bucket for goal/current body photos, standard Supabase
-- private-bucket + user-scoped-path RLS pattern -- first Storage usage in
-- this codebase, so this follows Supabase's documented convention rather
-- than an existing precedent: path prefix {auth.uid()}/... gates all four
-- operations. Feature is client-side flagged off (Config.enableBodyPhotoUpload)
-- pending legal review of the storage/consent copy.

insert into storage.buckets (id, name, public)
values ('body-photos', 'body-photos', false)
on conflict (id) do nothing;

create policy "body_photos_select_own" on storage.objects
  for select using (bucket_id = 'body-photos' and (storage.foldername(name))[1] = auth.uid()::text);

create policy "body_photos_insert_own" on storage.objects
  for insert with check (bucket_id = 'body-photos' and (storage.foldername(name))[1] = auth.uid()::text);

create policy "body_photos_update_own" on storage.objects
  for update using (bucket_id = 'body-photos' and (storage.foldername(name))[1] = auth.uid()::text);

create policy "body_photos_delete_own" on storage.objects
  for delete using (bucket_id = 'body-photos' and (storage.foldername(name))[1] = auth.uid()::text);
