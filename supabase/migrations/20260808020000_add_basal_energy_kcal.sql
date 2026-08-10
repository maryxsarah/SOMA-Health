-- Coaching personalization plan Phase 1 (docs/coaching-personalization-plan.md):
-- measured-BMR nutrition override. HealthKit's basalEnergyBurned (trailing
-- 24h cumulative, summed client-side same as fetchRecentAverageSteps) is
-- the only device-level resting-energy signal this app has access to --
-- Whoop/Oura are not wired to fetch anything RMR/BMR-like today. Lives on
-- daily_snapshot, source='healthkit', same per-day/per-source shape as
-- resting_hr. Nullable: most rows (other sources, or a day HealthKit
-- reported nothing) won't have it.
alter table daily_snapshot
  add column basal_energy_kcal numeric;
