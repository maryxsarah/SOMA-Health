-- parse-goal-assignment writes this source value; the CHECK must allow it
-- from day one, unlike the meal endpoints (see BUG-92).
alter table ai_generation_log drop constraint ai_generation_log_source_check;
alter table ai_generation_log add constraint ai_generation_log_source_check
  check (source in ('suggestion', 'gym_photo', 'addon_suggestion', 'meal_text_estimate', 'meal_rating', 'goal_assignment_parse'));
