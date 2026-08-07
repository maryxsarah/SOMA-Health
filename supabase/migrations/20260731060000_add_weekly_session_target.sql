-- Real, settable weekly session-count target -- shown on the restyled
-- Profile screen alongside actual progress (workouts logged this week),
-- computed client-side from the existing workout_log table, not a new
-- derived/stored count.
alter table users add column weekly_session_target integer check (weekly_session_target is null or (weekly_session_target between 1 and 14));
