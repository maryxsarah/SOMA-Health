-- Snapshots the actual AI-generated plan (blocks/exercises/etc.) at the
-- moment a workout is logged, so Training History can show real
-- exercise-level detail per day instead of just title/body_part. Nullable
-- -- a workout logged with no plan in scope (shouldn't normally happen,
-- since "Mark Workout Complete" only enables once a plan is generated)
-- falls back to today's flat display.

alter table workout_log add column plan_snapshot jsonb;
