-- HealthKit-originated workouts, synced from the device so they persist
-- server-side (previously HomeView.loadTimeline() only held these
-- in-memory via HealthKitManager.fetchTodaysWorkouts(), never sent
-- anywhere). Distinct from workout_log (user-completed AI-plan workouts)
-- and from the Whoop/Oura provider timeline (fetch-workout-timeline),
-- which is never HealthKit-sourced.
--
-- Client-writable via RLS, same pattern as workout_log -- this is the
-- user's own device data, not sensitive server-derived data.

create table healthkit_workout_sync (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references users(id) on delete cascade,
  source text not null default 'apple_health',
  start_time timestamptz not null,
  title text not null,
  duration_minutes integer not null,
  calories integer,
  synced_at timestamptz not null default now(),
  unique (user_id, source, start_time)
);

alter table healthkit_workout_sync enable row level security;

create policy "healthkit_workout_sync_select_own" on healthkit_workout_sync
  for select using (auth.uid() = user_id);

create policy "healthkit_workout_sync_insert_own" on healthkit_workout_sync
  for insert with check (auth.uid() = user_id);
