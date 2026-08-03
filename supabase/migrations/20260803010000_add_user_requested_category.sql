-- User-initiated "I need a rest/active-recovery day" override, distinct
-- from every cap above (those are computed from health data; this is a
-- direct user request that overrides the computed category outright,
-- regardless of what readiness/sleep/HRV/etc. would otherwise produce).
-- Nullable: null means no override is active today. Reuses category's own
-- vocabulary rather than introducing a new one -- "rest" or "light" are
-- the only two a user would ever ask for here.
alter table daily_recommendation add column user_requested_category text
  check (user_requested_category is null or user_requested_category in ('rest', 'light'));
