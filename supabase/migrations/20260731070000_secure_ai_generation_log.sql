-- ai_generation_log (added in 20260731010000) was never given row level
-- security -- a real gap: with RLS disabled, the anon key could read every
-- user's generation log, not just their own, same class of issue every
-- other per-user table in this schema (daily_snapshot, daily_recommendation,
-- workout_log, etc.) already guards against. Writes stay service-role only
-- (Edge Functions), matching those same tables -- only a SELECT policy is
-- added here, for the new client-facing "scan streak" read.
alter table ai_generation_log enable row level security;

create policy "ai_generation_log_select_own" on ai_generation_log
  for select using (auth.uid() = user_id);
