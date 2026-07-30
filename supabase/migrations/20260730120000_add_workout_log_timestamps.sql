-- Real workout start/end, distinct from completed_at (the timestamp of
-- the "log it" API call itself, not when the workout actually happened).
-- Nullable -- older logs, and any path that doesn't capture a start time,
-- fall back to the existing date-only display. Needed to match wearable
-- heart-rate data against the workout's EXACT time window rather than the
-- whole day.

alter table workout_log add column started_at timestamptz;
alter table workout_log add column ended_at timestamptz;
