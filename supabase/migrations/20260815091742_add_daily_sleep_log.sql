-- One-tap "how long did you sleep?" manual check-in for users without a
-- connected wearable -- same shape as daily_mood (user-entered content, no
-- derived/safety logic, client-writable directly via RLS). One row per user
-- per day; a wearable-sourced daily_snapshot.sleep_hours always takes
-- priority over this in the UI when both exist.
--
-- Timestamped with a non-round time-of-day, not 20260815000000 -- a round
-- top-of-day prefix is exactly what already collided twice on this repo
-- (see 20260808050000_add_known_lifts_retimestamped.sql and
-- 20260808060000_add_daily_mood_retimestamped.sql): two branches landing a
-- same-day migration with an identical prefix causes Supabase's migration
-- history to silently skip one file's CREATE TABLE entirely.
create table if not exists daily_sleep_log (
  user_id uuid references users(id) on delete cascade,
  date date not null,
  bucket text not null check (bucket in ('under_6', 'six_seven', 'seven_eight', 'eight_plus')),
  logged_at timestamptz not null default now(),
  primary key (user_id, date)
);

alter table daily_sleep_log enable row level security;

create policy "daily_sleep_log_select_own" on daily_sleep_log
  for select using (auth.uid() = user_id);

create policy "daily_sleep_log_insert_own" on daily_sleep_log
  for insert with check (auth.uid() = user_id);

create policy "daily_sleep_log_update_own" on daily_sleep_log
  for update using (auth.uid() = user_id);
