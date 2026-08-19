-- pantry_items: user-writable, structured "what I have at home" list --
-- a persistent input to generate-meal-recommendation, replacing the
-- ad-hoc `ingredients` string the user previously had to retype every
-- call. Same client-direct-write RLS shape as meal_log (select/insert/
-- update/delete own via auth.uid() = user_id), NOT the service-role-only
-- shape ai_workout_plan/gym_workout_plan use, since this table is meant
-- to be edited freely from the UI at any time as the fridge/pantry
-- actually changes through the week.
--
-- quantity is numeric and unit is separate free text ("cups", "g",
-- "cloves") -- both optional, since a bare "salt" with no amount is a
-- completely normal pantry entry. This is the simplest shape that's
-- still genuinely structured, rather than one free-text blob.
create table pantry_items (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references users(id) on delete cascade,
  name text not null,
  quantity numeric,
  unit text,
  updated_at timestamptz not null default now()
);

alter table pantry_items enable row level security;

create policy "pantry_items_select_own" on pantry_items
  for select using (auth.uid() = user_id);
create policy "pantry_items_insert_own" on pantry_items
  for insert with check (auth.uid() = user_id);
create policy "pantry_items_update_own" on pantry_items
  for update using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "pantry_items_delete_own" on pantry_items
  for delete using (auth.uid() = user_id);

-- daily_meal_plan: cache for the "Today's meal plan" autopilot, mirroring
-- gym_workout_plan's (user_id, date, equipment_signature) shape exactly
-- (see 20260728020000_add_gym_workout_plan_cache.sql). pantry_signature
-- is computed SERVER-SIDE inside generate-meal-recommendation from the
-- user's current pantry_items (sorted + joined, see pantrySignature.ts),
-- never client-supplied, so the client cannot force a cache hit/miss.
-- Select-only RLS; all writes go through the service-role client inside
-- the Edge Function, same pattern as ai_workout_plan/gym_workout_plan.
create table daily_meal_plan (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references users(id) on delete cascade,
  date date not null,
  pantry_signature text not null,
  category text,
  recommendation jsonb not null,
  created_at timestamptz not null default now(),
  unique (user_id, date, pantry_signature)
);

alter table daily_meal_plan enable row level security;

create policy "daily_meal_plan_select_own" on daily_meal_plan
  for select using (auth.uid() = user_id);

-- The daily-autopilot generation gets its own ai_generation_log source
-- and flat quota ("meal_recommendation_daily", 5/day), separate from
-- 'meal_recommendation' (the on-demand "What can I make?" quota, 20/day)
-- -- an automatic once-per-pantry-change generation shouldn't eat the
-- user's on-demand budget. Widened from the current live list (verified
-- against 20260817133251_add_affirmations.sql, the latest widening
-- migration) -- same "widen from day one" lesson as BUG-92.
alter table ai_generation_log drop constraint ai_generation_log_source_check;
alter table ai_generation_log add constraint ai_generation_log_source_check
  check (source in ('suggestion', 'gym_photo', 'addon_suggestion', 'meal_text_estimate', 'meal_rating', 'goal_assignment_parse', 'meal_recommendation', 'exercise_translation', 'affirmation', 'meal_recommendation_daily'));
