-- Self-reported pregnancy status -- one of three deterministic, server-
-- side safety-guardrail triggers for the gym-photo-workout feature (see
-- supabase/functions/_shared/safetyFlags.ts). Nullable/unset by default:
-- never assumed, only set when the user explicitly reports it from
-- ProfileView, same optional-field pattern as experience_level.

alter table users
  add column pregnancy boolean;

-- Existing RLS policy (auth.uid() = id) already covers this column; no
-- policy changes needed.
