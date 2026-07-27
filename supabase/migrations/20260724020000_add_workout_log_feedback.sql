-- Free-text feedback captured when the user logs a workout as complete
-- (e.g. "I like doing 5-10min incline treadmill before my workout").
-- generate-workout-plan folds recent non-null feedback into future plans
-- for a similar workout, so a stated preference actually sticks rather
-- than needing to be re-typed every time.

alter table workout_log
  add column feedback text;
