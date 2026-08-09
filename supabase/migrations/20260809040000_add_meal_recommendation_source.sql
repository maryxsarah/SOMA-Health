-- generate-meal-recommendation ("What can I make?") writes two new source
-- values that both need their CHECK constraint widened before first use,
-- same "widen from day one" lesson as BUG-92 (see
-- 20260806090000_widen_ai_generation_log_source_goal_assignment.sql):
--
-- ai_generation_log.source gains 'meal_recommendation' -- one row per
-- generate-meal-recommendation call, for its own flat daily rate limit
-- (checkFlatDailyLimit), independent of meal_text_estimate/meal_rating.
--
-- meal_log.source gains 'recipe_ai' -- written only when the user taps
-- "Log this meal" on a generated recommendation; distinct from 'text_ai'
-- (a freeform description Claude turned into numbers) since this entry's
-- macros came from a full recipe the user actually cooked, not a
-- description of something already eaten.
alter table ai_generation_log drop constraint ai_generation_log_source_check;
alter table ai_generation_log add constraint ai_generation_log_source_check
  check (source in ('suggestion', 'gym_photo', 'addon_suggestion', 'meal_text_estimate', 'meal_rating', 'goal_assignment_parse', 'meal_recommendation'));

alter table meal_log drop constraint meal_log_source_check;
alter table meal_log add constraint meal_log_source_check
  check (source in ('manual', 'photo', 'text_ai', 'recipe_ai'));
