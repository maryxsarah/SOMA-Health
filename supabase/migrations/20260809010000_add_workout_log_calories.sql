-- Structured calorie total per workout_log row -- previously calories only
-- ever existed as free text buried inside `feedback` for a device-detected
-- entry (HomeView's autoLogDeviceDetectedWorkoutIfNeeded wrote "... -- N
-- kcal burned" into the feedback string) and didn't exist at all for
-- ai_plan/manual entries. CompletedWorkoutView backfills both columns
-- lazily the first time a log missing them is opened (same pattern as
-- NutritionView's autoRateUnratedEntries): a real HealthKit/wearable number
-- for the log's started_at/ended_at window when one exists, else a MET-
-- based estimate from category + duration + the user's weight, explicitly
-- flagged as such via calories_estimated so the UI never presents a guess
-- as a measured fact.
--
-- Both nullable -- nil means "not backfilled yet" (every existing row) or
-- "couldn't be computed at all" (no device data AND no weight on file for
-- an estimate), never a fabricated zero.
alter table workout_log add column calories_burned integer;
alter table workout_log add column calories_estimated boolean not null default false;
