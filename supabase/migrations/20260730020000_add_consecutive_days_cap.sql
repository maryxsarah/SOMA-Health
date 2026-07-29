-- Tracks whether today's category was capped down to 'light' active
-- recovery because the user has trained 5+ consecutive prior days,
-- regardless of how strong today's recovery signals looked. Mirrors the
-- existing sleep_cap_applied/injury_cap_applied/load_cap_applied columns.

alter table daily_recommendation
  add column consecutive_days_cap_applied boolean not null default false;
