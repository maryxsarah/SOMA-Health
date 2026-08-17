-- Feedback spec item 8: nutrition scoring rewrite.
--
-- score_breakdown: the exact modifiers ("<sign>:<key>" entries, e.g.
-- "-:alcohol") that produced meal_log.score -- see rate-meal/scoreMeal.ts.
-- Lets MealDetailView show a +/- breakdown instead of a bare number, and
-- lets rate-meal clear a stale rating (set back to null) when macros are
-- edited, without losing the fact that it once had a real breakdown shape.
--
-- meal_log_update_own: previously only select/insert/delete existed --
-- there was no way to correct a wrong AI-estimated or mistyped entry once
-- logged. Same auth.uid() = user_id shape as every other policy on this
-- table.
alter table meal_log add column score_breakdown text[];

create policy "meal_log_update_own" on meal_log
  for update using (auth.uid() = user_id) with check (auth.uid() = user_id);
