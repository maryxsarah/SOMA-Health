-- Adds recent-training-load tracking so Whoop cycles/workout and Oura
-- workout data (not just morning recovery/readiness) factor into the
-- recommendation, mirroring the existing sleep_cap_applied /
-- injury_cap_applied pattern with an independent load_cap_applied.

alter table daily_snapshot
  -- Whoop day strain (0-21 scale) or Oura's count of recent hard-intensity
  -- workouts -- a rough "how much load recently" signal per source, stored
  -- for transparency/future display, not itself a decision-engine input.
  add column strain_score numeric;

alter table daily_recommendation
  add column load_cap_applied boolean not null default false;

-- Existing RLS policies (auth.uid() = user_id) already cover these new
-- columns; no policy changes needed.
