-- How much of a real read the day's recommendation is.
--
-- The HealthKit-only path assembles a band from whatever the watch happened
-- to record. When only one signal is available (no overnight wear, or not
-- enough history for a baseline yet) the band can swing on that single
-- number, and the user has no way to tell that apart from a confident read
-- backed by a Whoop recovery score. Four identical "Moderate" days with no
-- explanation is what made the feature feel broken to testers.
--
-- Deliberately a separate column rather than new `reason` values: `reason`
-- carries a CHECK constraint and is already the diagnostic "which band and
-- from which provider" axis. Confidence is orthogonal to both -- a low-
-- confidence read can still be any band.
--
-- Nullable with no default and no backfill: rows written before this column
-- existed genuinely have unknown confidence, and claiming 'high' for them
-- would be inventing a fact. The app shows no caveat when it is null.

alter table daily_recommendation
  add column data_confidence text
  check (data_confidence in ('high', 'low'));
