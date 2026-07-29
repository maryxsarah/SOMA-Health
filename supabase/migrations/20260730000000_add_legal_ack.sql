-- Durable record of onboarding legal acknowledgment (Terms of Service +
-- Privacy Policy + health disclaimer). Written once per successful gated
-- sign-in from SupabaseClient's signIn*/signUp* methods -- the client can
-- only reach those calls after checking the acknowledgment box in
-- OnboardingView, so every write here represents a real, timestamped
-- acknowledgment, not a guess.

alter table users add column legal_ack_at timestamptz;
alter table users add column legal_ack_version text;
