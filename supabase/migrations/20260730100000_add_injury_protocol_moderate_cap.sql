-- Mirrors injury_protocol_cap_applied (severe -> light) with a lesser cap
-- for moderate-severity active/recovering protocols: push_hard -> moderate
-- only, never all the way to light.

alter table daily_recommendation
  add column injury_protocol_moderate_cap_applied boolean not null default false;
