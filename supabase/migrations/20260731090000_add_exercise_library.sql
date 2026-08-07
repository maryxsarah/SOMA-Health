-- Exercise-media library, imported once from the Free Exercise DB
-- (https://github.com/yuhonas/free-exercise-db, The Unlicense / public
-- domain -- verified directly against the repo's LICENSE.md, safe for
-- commercial use with no attribution requirement). Not user data -- a
-- shared, read-only reference table, same "closed vocabulary" pattern
-- this codebase already uses for equipment/goal tags (see
-- _shared/equipment.ts, _shared/goalTags.ts), so generate-workout-plan
-- can be constrained to names that are GUARANTEED to have real, correctly
-- matched media rather than relying on fuzzy string matching at render
-- time.
create table exercise_library (
  id text primary key,
  name text not null,
  force text,
  level text,
  mechanic text,
  equipment text,
  primary_muscles text[] not null default '{}',
  secondary_muscles text[] not null default '{}',
  instructions text[] not null default '{}',
  category text,
  image_paths text[] not null default '{}'
);

create index exercise_library_name_idx on exercise_library (name);

-- Read-only, not user-scoped -- same public-reference-data shape as, say,
-- a future equipment catalog would be. Everyone signed in can read;
-- nothing here is written by the client (import is a one-time,
-- service-role-only operation).
alter table exercise_library enable row level security;

create policy "exercise_library_select_all" on exercise_library
  for select using (true);

-- Public bucket (unlike body-photos): these are generic, freely-licensed
-- stock exercise photos, not personal user content, so plain public URLs
-- are simpler and avoid a signed-URL round trip on every exercise view.
insert into storage.buckets (id, name, public)
values ('exercise-media', 'exercise-media', true)
on conflict (id) do nothing;

do $$
begin
  create policy "exercise_media_public_read" on storage.objects
    for select using (bucket_id = 'exercise-media');
exception
  when insufficient_privilege then
    raise notice 'Skipped exercise-media storage read policy (role lacks storage.objects ownership) -- create it via Dashboard -> Storage -> exercise-media -> Policies: select, bucket_id = ''exercise-media''.';
  when duplicate_object then
    null;
end $$;
