-- User-logged completed workouts: backs the "Log workout" button on
-- RecommendationDetailView, the calendar day drill-down, and lets the next
-- day's workout selection deprioritize repeating the same body part on
-- consecutive days (a real training-load signal, not just avoiding a
-- literal title repeat). Client-writable via RLS (no service-role Edge
-- Function needed) -- this is user-entered content, not derived health
-- data, same category as e.g. the users.goals array.

create table workout_log (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references users(id) on delete cascade,
  date date not null,
  title text not null,
  body_part text not null,
  category text not null check (category in ('rest','light','moderate','push_hard')),
  completed_at timestamptz not null default now()
);

alter table workout_log enable row level security;

create policy "workout_log_select_own" on workout_log
  for select using (auth.uid() = user_id);

create policy "workout_log_insert_own" on workout_log
  for insert with check (auth.uid() = user_id);

create policy "workout_log_delete_own" on workout_log
  for delete using (auth.uid() = user_id);
