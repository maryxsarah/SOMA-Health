-- Profile-picture upload: a private bucket + user-scoped-path RLS policy,
-- same convention as body-photos (20260729010000) and coach-assignments.
-- Unlike body-photos, this is a single fixed path per user (no history
-- needed for a profile picture) -- each upload overwrites the prior one
-- via Storage's upsert header.

alter table users add column if not exists avatar_photo_path text;

insert into storage.buckets (id, name, public)
values ('avatars', 'avatars', false)
on conflict (id) do nothing;

-- See body-photos' own migration comment: CREATE POLICY on
-- storage.objects requires table ownership, which `db push` (running as
-- postgres) may lack on hosted Supabase -- guarded so a missing
-- privilege skips with a notice instead of failing the whole chain.
do $$
begin
  drop policy if exists "avatars_select_own" on storage.objects;
  drop policy if exists "avatars_insert_own" on storage.objects;
  drop policy if exists "avatars_update_own" on storage.objects;
  drop policy if exists "avatars_delete_own" on storage.objects;

  create policy "avatars_select_own" on storage.objects
    for select using (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text);

  create policy "avatars_insert_own" on storage.objects
    for insert with check (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text);

  create policy "avatars_update_own" on storage.objects
    for update using (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text);

  create policy "avatars_delete_own" on storage.objects
    for delete using (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text);
exception
  when insufficient_privilege then
    raise notice 'Skipped avatars storage policies (role lacks storage.objects ownership) -- create them via the dashboard: Storage -> avatars -> Policies, select/insert/update/delete each scoped to bucket_id = ''avatars'' and (storage.foldername(name))[1] = auth.uid()::text.';
end $$;
