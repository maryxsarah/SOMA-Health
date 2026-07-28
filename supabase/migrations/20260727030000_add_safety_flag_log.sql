-- Audit trail for the gym-photo-workout feature's safety guardrail
-- (supabase/functions/_shared/safetyFlags.ts): every time a request is
-- blocked because of a noted injury, an abnormal resting-HR deviation, or
-- reported pregnancy, one row is logged here. This is a safety/audit
-- record, not user-editable content -- all writes go through the
-- service-role client only, same pattern as wearable_tokens/
-- daily_recommendation. Users may read their own rows (transparency) but
-- never write or delete them.

create table safety_flag_log (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references users(id) on delete cascade,
  date date not null,
  flag_type text not null check (flag_type in ('injury', 'abnormal_resting_hr', 'pregnancy')),
  detail text,
  created_at timestamptz not null default now()
);

alter table safety_flag_log enable row level security;

create policy "safety_flag_log_select_own" on safety_flag_log
  for select using (auth.uid() = user_id);

-- No insert/update/delete policies -- writes happen only via the
-- service-role client inside the gym-photo Edge Functions.
