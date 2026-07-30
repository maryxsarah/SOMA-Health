-- Mirrors sleep_cap_applied/injury_cap_applied/load_cap_applied/
-- consecutive_days_cap_applied: whether today's category was forced down
-- to 'light' because a severe-tier injury_recovery_state row is currently
-- active/recovering, regardless of how strong today's recovery signals
-- looked. Per product decision, this is a soft cap (like the others),
-- not a hard block -- generation still proceeds with the contraindication
-- map's exclusions applied.

alter table daily_recommendation
  add column injury_protocol_cap_applied boolean not null default false;
