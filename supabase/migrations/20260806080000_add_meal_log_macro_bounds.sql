-- Generous sanity bounds -- guards against garbage/negative values, not a
-- real constraint on any actual meal.
alter table meal_log add constraint meal_log_calories_range check (calories between 0 and 5000);
alter table meal_log add constraint meal_log_protein_g_range check (protein_g between 0 and 500);
alter table meal_log add constraint meal_log_carbs_g_range check (carbs_g is null or carbs_g between 0 and 500);
alter table meal_log add constraint meal_log_fat_g_range check (fat_g is null or fat_g between 0 and 500);
