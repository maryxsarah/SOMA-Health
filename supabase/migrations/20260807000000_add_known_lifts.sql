-- Optional, user-stated real working weights for the 5 bilateral load-
-- guidance patterns (squat_pattern, hinge_pattern, overhead_press,
-- horizontal_press, row_pull -- same keys as generate-workout-plan/
-- loadGuidance.ts's LOAD_FRACTION_OF_BODYWEIGHT), kg values, e.g.
-- {"hinge_pattern": 100}. Real feedback: a self-described non-
-- powerlifter was prescribed 125-135kg for a deadlift from the
-- population-level bodyweight-ratio estimate alone -- "probably need to
-- ask the user about their strength levels." When a pattern has a value
-- here, buildLoadGuidance uses it directly instead of estimating.
alter table users add column known_lifts jsonb;
