-- Injury type (fixed set, not free text -- keeps the decision engine able
-- to act on it, same philosophy as injury_tags/injury_severity) and
-- self-reported pain level, both optional and separate from severity.
-- Parallel jsonb columns keyed by InjuryTag rawValue, mirroring
-- injury_severity's existing pattern exactly.

alter table users add column injury_type jsonb not null default '{}'::jsonb;
alter table users add column injury_pain_level jsonb not null default '{}'::jsonb;

-- Latest self-reported pain level at check-in time (1-10), nullable --
-- only injuries with an active injury_recovery_state row (moderate/severe)
-- ever get a check-in at all, per report-injury's mild-skip behavior.
alter table injury_recovery_state add column pain_level integer;
