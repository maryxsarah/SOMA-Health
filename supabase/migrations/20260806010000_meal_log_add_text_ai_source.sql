-- meal_log.source gains 'text_ai' -- an entry whose calories/macros were
-- first estimated by Claude from a free-text description (e.g. "2 eggs,
-- toast, and coffee with milk"), then reviewed/saved by the user via the
-- same LogMealView form as a plain manual entry. Distinct from 'manual'
-- (typed numbers directly) purely for future analytics -- both are
-- equally user-confirmed before they hit this table.
alter table meal_log drop constraint meal_log_source_check;
alter table meal_log add constraint meal_log_source_check
  check (source in ('manual', 'photo', 'text_ai'));
