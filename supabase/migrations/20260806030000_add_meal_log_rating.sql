-- Per-meal "how well does this support your goal" rating -- computed
-- once by rate-meal (Claude Haiku, given the meal's own macros/label,
-- the user's real nutrition_targets, and training_emphasis) and stored
-- here rather than recomputed every time the meal is viewed, so a
-- meal's rating never mysteriously changes between views and doesn't
-- cost a fresh API call each time. `verdict` is deliberately NOT a
-- column -- it's a pure function of score (see MealVerdict in the
-- Swift model), same "derive, don't duplicate" rule as
-- NutritionDayProgress's fractions.
alter table meal_log add column if not exists score integer check (score between 1 and 10);
alter table meal_log add column if not exists rationale text;
