-- Distinguishes a workout logged from an AI-generated suggestion/plan
-- ('ai_plan', the only kind that existed before this column) from one the
-- user typed in themselves for an activity Soma never suggested (a sport
-- session, a class, etc. -- see LogManualWorkoutView). Existing rows all
-- backfill to 'ai_plan' via the column default, which is accurate: every
-- row created before this migration really was AI-plan-sourced.
--
-- HomeView uses this to route "see today's workout" to the right detail
-- screen -- RecommendationDetailView (ai_plan, has suggestion titles to
-- match against) vs CompletedWorkoutView (manual, generic -- already
-- degrades gracefully with no plan_snapshot).
alter table workout_log add column source text not null default 'ai_plan'
  check (source in ('ai_plan', 'manual'));
