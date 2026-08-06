-- Goal Body feature: only genuinely new users columns. `blockers` (added
-- earlier, text[]) already covers "what's holding them back" -- this just
-- adds an optional free-text companion, same shape as injury_tags/
-- injury_notes. `journey_stage` is a distinct concept from
-- `experience_level` (training competency) and `workouts_per_week`
-- (current frequency): it's motivational/journey context ("just starting"
-- vs "returning after a break" vs "plateaued"), which neither existing
-- column captures.
alter table users
  add column height_cm numeric,
  add column journey_stage text check (
    journey_stage is null or journey_stage in (
      'just_starting', 'returning_after_break', 'consistent_but_plateaued', 'experienced'
    )
  ),
  add column blockers_notes text;

-- Qualitative-only training direction inferred from the existing goal/
-- current body-photo comparison (analyze-body-photo) -- kept as its own
-- column for auditability/debugging, same reason pre_cap_category is kept
-- on daily_recommendation. NOT read by generate-workout-plan directly:
-- the existing body_photo_emphasis_tags -> buildPrompt signal is the real
-- integration point, deliberately kept separate from users.goals so "the
-- user said X" is never indistinguishable from "the model guessed X".
alter table users
  add column training_emphasis text check (
    training_emphasis is null or training_emphasis in ('cut', 'recomp', 'bulk', 'maintain')
  );
