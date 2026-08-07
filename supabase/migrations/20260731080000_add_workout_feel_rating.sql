-- Real, settable "how it felt" rating per logged workout -- shown on the
-- completed-workout screen as 3 selectable chips (Easy / Hard but good /
-- Too much), editable afterward via "Edit this log". Purely a UI/copy
-- layer (drives a fixed consequence sentence client-side) -- it does not
-- feed back into generate-recommendation's actual capping logic.
alter table workout_log add column feel_rating text check (feel_rating is null or feel_rating in ('easy', 'hard_but_good', 'too_much'));
