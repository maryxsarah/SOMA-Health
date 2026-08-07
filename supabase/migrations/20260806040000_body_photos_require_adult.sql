-- Age gate previously only covered analyze-body-photo, not the upload
-- itself. RLS is the only enforcement point available on that path.
do $$
begin
  drop policy if exists "body_photos_insert_own" on storage.objects;
  drop policy if exists "body_photos_update_own" on storage.objects;

  create policy "body_photos_insert_own" on storage.objects
    for insert with check (
      bucket_id = 'body-photos'
      and (storage.foldername(name))[1] = auth.uid()::text
      and exists (
        select 1 from users u
        where u.id = auth.uid()
          and u.date_of_birth is not null
          and u.date_of_birth <= (current_date - interval '18 years')::date
      )
    );

  create policy "body_photos_update_own" on storage.objects
    for update using (
      bucket_id = 'body-photos'
      and (storage.foldername(name))[1] = auth.uid()::text
      and exists (
        select 1 from users u
        where u.id = auth.uid()
          and u.date_of_birth is not null
          and u.date_of_birth <= (current_date - interval '18 years')::date
      )
    );
exception
  when insufficient_privilege then
    raise notice 'Could not recreate body-photos insert/update policies (role lacks storage.objects ownership) -- recreate them manually via Dashboard -> Storage -> body-photos -> Policies, adding: exists (select 1 from users u where u.id = auth.uid() and u.date_of_birth is not null and u.date_of_birth <= (current_date - interval ''18 years'')::date).';
end $$;
