-- Adds a distinct 'insufficient_data' reason value: the zero-HealthKit-signal
-- case (day 1, before any baseline) previously fell through to
-- 'healthkit_medium', indistinguishable from a real medium-confidence read.
-- The category/message stay unchanged (still a cautious 'moderate' session)
-- -- only the presented "why" becomes honest about the missing data.

alter table daily_recommendation drop constraint daily_recommendation_reason_check;

alter table daily_recommendation add constraint daily_recommendation_reason_check
  check (reason in (
    'whoop_high', 'whoop_medium', 'whoop_low',
    'oura_high', 'oura_medium_high', 'oura_medium', 'oura_low',
    'healthkit_high', 'healthkit_medium', 'healthkit_low',
    'insufficient_data',
    'unknown'
  ));
