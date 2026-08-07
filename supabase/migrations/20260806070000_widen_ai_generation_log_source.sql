-- parse-meal-text/rate-meal have written these source values since they
-- shipped, but the CHECK never allowed them -- every insert was silently failing.
alter table ai_generation_log drop constraint ai_generation_log_source_check;
alter table ai_generation_log add constraint ai_generation_log_source_check
  check (source in ('suggestion', 'gym_photo', 'addon_suggestion', 'meal_text_estimate', 'meal_rating'));
