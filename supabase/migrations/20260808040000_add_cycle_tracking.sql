-- Coaching personalization plan Phase 5 (docs/coaching-personalization-plan.md):
-- weekly-anchor-session-style opt-in cycle-phase tracking. Same shape as
-- users.pregnancy/pregnancy_week -- nullable, unconstrained by default,
-- never assumed, only set when the user explicitly reports it from
-- ProfileView (see pregnancyEditor's own precedent; there is deliberately
-- no separate "opted in" boolean, same as pregnancy: the presence of
-- last_period_start_date IS the opt-in signal). Training-hook only this
-- phase (sexAwareGuidance.ts) -- see the design doc for why nutrition was
-- explicitly deferred (no daily-cadence write site for nutrition_targets
-- to hook into today).
--
-- typical_cycle_length_days is independently nullable (a user may know
-- their last period date but not their typical length) -- server-side
-- derivation falls back to a population default (28 days) when absent,
-- same "personal value overrides population estimate, never required"
-- pattern as known_lifts/loadGuidance.ts. No future-date constraint on
-- last_period_start_date: the derivation function fails safe (treats a
-- nonsensical date as "no usable data") rather than the DB rejecting the
-- write, same client-is-the-single-writer trust model as every other
-- users column (goals, country, city, ...).
alter table users
  add column last_period_start_date date,
  add column typical_cycle_length_days integer check (
    typical_cycle_length_days is null or (typical_cycle_length_days between 21 and 35)
  );
