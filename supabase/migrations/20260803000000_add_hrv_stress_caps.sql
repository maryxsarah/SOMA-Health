-- Same independent-cap shape as sleep_cap_applied/injury_cap_applied/
-- load_cap_applied/pregnancy_cap_applied/volume_cap_applied: caps a
-- moderate/push_hard day down to "light" using signals (HRV, Oura stress
-- minutes) that were already stored in daily_snapshot but never read back
-- for capping before -- see generate-recommendation/index.ts.
alter table daily_recommendation add column hrv_cap_applied boolean not null default false;
alter table daily_recommendation add column stress_cap_applied boolean not null default false;
