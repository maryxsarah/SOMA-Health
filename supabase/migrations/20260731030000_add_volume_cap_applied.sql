-- Same independent-cap shape as sleep_cap_applied/injury_cap_applied/
-- load_cap_applied/pregnancy_cap_applied: caps a day down to "light" when
-- recent training days (rolling 7-day window, gaps allowed) meet or exceed
-- a volume-landmark-derived threshold -- catches accumulated fatigue that
-- the existing consecutive_days_cap_applied's streak-based check misses
-- when a single rest day breaks the streak.
alter table daily_recommendation add column volume_cap_applied boolean not null default false;
