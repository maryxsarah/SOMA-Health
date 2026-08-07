-- Fixes a timezone-drift bug in 20260806040000's age gate: `current_date`
-- resolves against the DB session's timezone (Supabase defaults to UTC),
-- not the user's device-local calendar day. A user east of UTC (e.g.
-- UTC+13) could turn 18 "today" on their device while the DB's current_date
-- is still "yesterday", so `date_of_birth <= (current_date - 18y)` would
-- evaluate false and silently reject a legitimately-adult user's photo
-- upload/update. The client-side gate (AgeGate.swift) already uses the
-- device's real local calendar via Calendar.current -- this policy is a
-- server-side backstop, not the primary check, so leaning generous by
-- widening the reference day by one is the right tradeoff: it can never
-- again reject someone the client already correctly counted as 18.
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
          and u.date_of_birth <= (current_date + interval '1 day' - interval '18 years')::date
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
          and u.date_of_birth <= (current_date + interval '1 day' - interval '18 years')::date
      )
    );
exception
  when insufficient_privilege then
    raise notice 'Could not recreate body-photos insert/update policies (role lacks storage.objects ownership) -- recreate them manually via Dashboard -> Storage -> body-photos -> Policies, adding: exists (select 1 from users u where u.id = auth.uid() and u.date_of_birth is not null and u.date_of_birth <= (current_date + interval ''1 day'' - interval ''18 years'')::date).';
end $$;
