-- Coaching personalization plan Phase 4 (docs/coaching-personalization-plan.md):
-- weekly anchor-session concept. A recurring class/activity (e.g. a
-- Tuesday hot yoga class, a Saturday tennis league) the rest of the week
-- should be scheduled around. `anchor_session_days` reuses the EXACT same
-- weekday convention user_goal.schedule_days already uses (0=Sun..6=Sat,
-- JS getUTCDay) and the same client-side WeekdayMiniPicker component, so
-- generate-workout-plan's forward-looking logic can treat it identically.
-- No check constraints on either column -- same "client is the single
-- writer" trust model as country/city/goals; day-value range validation
-- (0..6) happens client-side, same as schedule_days already does (see
-- create-goal/index.ts's own validation, not a DB constraint there either).
alter table users
  add column anchor_session_name text,
  add column anchor_session_days int[] not null default '{}';
