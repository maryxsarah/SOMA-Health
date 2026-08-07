-- Per-stage sleep breakdown -- Whoop's stage_summary, HealthKit's
-- classified sleep-analysis samples, and Oura's sleep payload all already
-- report these; they were computed and then discarded before persistence.
-- Feeds the dashboard's sleep-stage chart (Epic A). Nullable: not every
-- source/night reports every stage.
alter table daily_snapshot
  add column sleep_light_hours numeric,
  add column sleep_deep_hours numeric,
  add column sleep_rem_hours numeric,
  add column sleep_awake_hours numeric;
