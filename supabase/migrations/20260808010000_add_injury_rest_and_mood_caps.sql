-- Two new independent caps on generate-recommendation/index.ts's category
-- decision, real feedback: "all the customization the user provides needs
-- to be considered for the workout ... when the user shared a specific
-- injury, if needed a rest day needs to be recommended."
--
-- injury_protocol_rest_applied: a severe injury_recovery_state protocol
-- that was just reported (or escalated to severe) in the last ~24h, or
-- that's been trending worse for 3+ consecutive check-ins, now forces the
-- day to full "rest" rather than the existing injury cap's ceiling of
-- "light" -- see injuryProtocolRestApplied in generate-recommendation.
--
-- mood_cap_applied: today's daily_mood check-in (rating 1-2 of 5) can
-- downgrade the day one step, same asymmetric-caution shape as every
-- other cap here (a good mood never upgrades the day) -- see
-- moodCapApplied in generate-recommendation. Depends on the daily_mood
-- table (20260807010000_add_daily_mood.sql), also still held.
alter table daily_recommendation add column injury_protocol_rest_applied boolean not null default false;
alter table daily_recommendation add column mood_cap_applied boolean not null default false;
