-- Oura's daily stress metric (minutes in a high-stress state today) --
-- rounds out the health-data picture already fed into AI workout plan
-- generation (recovery/readiness, HRV, sleep, resting HR, strain) with
-- the one signal that was still missing for Oura users.

alter table daily_snapshot
  add column stress_score numeric;
