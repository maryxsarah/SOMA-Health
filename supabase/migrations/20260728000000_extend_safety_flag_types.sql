-- The gym-photo guardrail no longer hard-blocks on a noted injury; it now
-- excludes high-impact templates and still produces a workout, matching
-- what the normal AI-plan path already does (RecommendationDetailView
-- filters highImpact suggestions, and generate-recommendation has already
-- capped the day's category via injuryCapApplied before this code runs).
-- See supabase/functions/_shared/safetyFlags.ts for the full reasoning.
--
-- That soft adjustment is still worth an audit row, but under a flag_type
-- that does not claim the request was blocked. Without widening this CHECK
-- first, the insert would raise and take the whole generation down for
-- exactly the users the guardrail exists to protect.
--
-- 'injury' stays permitted so any historical rows remain valid.

alter table safety_flag_log
  drop constraint if exists safety_flag_log_flag_type_check;

alter table safety_flag_log
  add constraint safety_flag_log_flag_type_check
  check (flag_type in (
    'injury',
    'injury_high_impact_excluded',
    'abnormal_resting_hr',
    'pregnancy'
  ));
