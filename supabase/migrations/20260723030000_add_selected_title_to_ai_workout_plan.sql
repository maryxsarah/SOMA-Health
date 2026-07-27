-- Fixes a real bug: ai_workout_plan was cached keyed only on (user_id,
-- date), so a user picking a *different* workout later the same day (or
-- any leftover row from earlier testing) would silently get back
-- whatever was generated for the first selection that day, regardless of
-- what they actually picked. generate-workout-plan now checks this column
-- against the incoming selection and regenerates on a mismatch instead of
-- blindly trusting any existing row for the date.

alter table ai_workout_plan
  add column selected_title text not null default '';

-- Existing RLS policy (auth.uid() = user_id) already covers this column;
-- no policy changes needed.
