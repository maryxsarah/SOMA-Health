-- Adds structured "why" tracking to daily_recommendation so the app can
-- show a fixed, template-driven explanation (no AI-generated text) for
-- why a given category was chosen, keyed off which provider/band drove
-- the decision plus whether the sleep safety cap fired.

alter table daily_recommendation
  add column reason text not null default 'unknown' check (reason in (
    'whoop_high', 'whoop_medium', 'whoop_low',
    'oura_high', 'oura_medium_high', 'oura_medium', 'oura_low',
    'healthkit_high', 'healthkit_medium', 'healthkit_low',
    'unknown'
  )),
  add column sleep_cap_applied boolean not null default false;

-- Existing RLS select policy on daily_recommendation (auth.uid() = user_id)
-- already covers these new columns; no policy changes needed.
