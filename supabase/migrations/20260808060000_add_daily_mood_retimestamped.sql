-- Re-timestamped re-application of 20260807010000_add_daily_mood.sql.
-- Same collision mechanism as 20260808050000_add_known_lifts_retimestamped.sql:
-- this branch's 20260807010000 prefix collides with a different migration
-- on another branch (add_volleyball_program_names.sql) that reached this
-- shared remote first, so the daily_mood table was never actually
-- created here despite `supabase migration list` reporting that
-- timestamp as applied. Confirmed via information_schema.tables showing
-- no daily_mood table on the remote. This is the root cause of "Couldn't
-- save that -- check your connection and try again." on every mood
-- check-in tap (logMood posts to a table that doesn't exist).
--
-- Original content, unchanged:
--
-- A simple daily "how are you feeling?" check-in -- real feedback: "it
-- would be nice to have some human-level metric that the app optimizes
-- ... showing that the metric improves with app usage." One row per
-- user per day, client-writable directly via RLS, same shape as
-- workout_log/meal_log (user-entered content, no derived/safety logic
-- involved, no service-role Edge Function needed).
create table daily_mood (
  user_id uuid references users(id) on delete cascade,
  date date not null,
  rating integer not null check (rating between 1 and 5),
  logged_at timestamptz not null default now(),
  primary key (user_id, date)
);

alter table daily_mood enable row level security;

create policy "daily_mood_select_own" on daily_mood
  for select using (auth.uid() = user_id);

create policy "daily_mood_insert_own" on daily_mood
  for insert with check (auth.uid() = user_id);

create policy "daily_mood_update_own" on daily_mood
  for update using (auth.uid() = user_id);
