-- Caches the AI-generated workout plan (exercises, sets/reps, weight
-- guidance, intensity, duration, how-to instructions) for a given user/day.
-- One row per (user_id, date) enforces the "1 generation per user per day"
-- cost cap discussed with the user -- generate-workout-plan checks this
-- table first and only calls the Anthropic API on a cache miss.

create table ai_workout_plan (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references users(id) on delete cascade,
  date date not null,
  category text not null check (category in ('rest','light','moderate','push_hard')),
  plan jsonb not null,
  created_at timestamptz not null default now(),
  unique (user_id, date)
);

alter table ai_workout_plan enable row level security;

create policy "ai_workout_plan_select_own" on ai_workout_plan
  for select using (auth.uid() = user_id);

-- Inserts/updates happen only via the service-role client inside
-- generate-workout-plan; no client-facing write policy, same pattern as
-- daily_snapshot / daily_recommendation.
