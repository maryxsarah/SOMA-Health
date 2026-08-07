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
