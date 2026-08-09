-- Backs the daily checklist card (HomeView, between the calendar strip and
-- the workout card). Design tradeoff, decided here rather than asked about:
--
-- Auto-checked items (log breakfast, hit step goal, feeling check-in,
-- complete workout) are NEVER stored here -- they're computed at read time
-- straight from meal_log/daily_mood/workout_log/HealthKit, exactly like
-- NutritionDayProgress derives from meal_log rather than duplicating a
-- "did they hit their macros" flag. Storing a second copy of that boolean
-- is exactly the kind of drift the rest of this codebase already avoids
-- (see NutritionDayProgress's own doc comment on the same principle).
--
-- What DOES need a real row here is anything with no other durable signal:
--   - the weekly progress-picture item's 7-day cadence (there's no photo-
--     update timestamp elsewhere to key off -- tapping through writes a
--     'progress_picture' row for today, and the 7-day window is computed
--     from the most recent one)
--   - the one-time onboarding-checklist items that have no clean
--     always-available signal (e.g. "review your first plan")
--   - the "day complete" marker itself, written once when every item for
--     that day is checked -- this is what the streak is computed from.
--     Recomputing "was every item checked on day X" retroactively from
--     raw logs would need that day's historical nutrition/step targets,
--     which aren't preserved (nutrition_targets is recomputed in place,
--     never a history table -- see its own migration comment), so a
--     same-day marker captured once, at the moment it becomes true, is the
--     only reliable source for a streak that reaches back past today.
--
-- One table, two scopes:
--   'daily'      -- date-scoped, unique per (user_id, item_key, date).
--                   item_key 'progress_picture' and '__day_complete__'
--                   both live here.
--   'onboarding' -- one-time, checked at most once ever per item_key.
--                   date is just "when it was completed" (informational),
--                   never part of the lookup -- app logic checks existence
--                   by (user_id, item_key) alone for this scope.
create table daily_checklist_state (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references users(id) on delete cascade,
  scope text not null check (scope in ('daily', 'onboarding')),
  item_key text not null,
  date date not null,
  checked_at timestamptz not null default now(),
  unique (user_id, item_key, date)
);

alter table daily_checklist_state enable row level security;

create policy "daily_checklist_state_select_own" on daily_checklist_state
  for select using (auth.uid() = user_id);

create policy "daily_checklist_state_insert_own" on daily_checklist_state
  for insert with check (auth.uid() = user_id);

create policy "daily_checklist_state_delete_own" on daily_checklist_state
  for delete using (auth.uid() = user_id);

-- Streak reads scan backward day-by-day from today's date -- keep it index-backed.
create index daily_checklist_state_user_date_idx on daily_checklist_state (user_id, date desc);
