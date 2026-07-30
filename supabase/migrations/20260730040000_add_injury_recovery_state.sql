-- Multi-day recovery-protocol/check-in state machine for a reported
-- injury. One row per (user, injury_tag). All writes go through the
-- service-role report-injury / record-injury-checkin Edge Functions --
-- the client can only read, never write directly, since the transition
-- logic (is this new/escalated? did the streak clear the protocol?) must
-- not be trustable to a raw client write, same reasoning as every other
-- server-computed decision in this app.
--
-- States: active (just reported/escalated, or check-ins trending worse) ->
-- recovering (check-ins trending better) -> cleared (5+ consecutive
-- 'better' check-ins while recovering). A stale check-in (3+ days) while
-- 'active' keeps the protocol's constraints applied rather than expiring
-- it -- fail closed, same philosophy as safetyFlags.ts's missing-data
-- handling. 'cleared' stops constraining generation; the tag itself stays
-- on users.injury_tags until the user removes it manually in Profile.

create table injury_recovery_state (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references users(id) on delete cascade,
  injury_tag text not null,
  severity text not null check (severity in ('mild', 'moderate', 'severe')),
  status text not null check (status in ('active', 'recovering', 'cleared')) default 'active',
  protocol_started_at timestamptz not null default now(),
  last_checkin_date date,
  last_checkin_response text check (last_checkin_response in ('better', 'same', 'worse')),
  consecutive_good_days integer not null default 0,
  consecutive_bad_days integer not null default 0,
  updated_at timestamptz not null default now(),
  unique (user_id, injury_tag)
);

alter table injury_recovery_state enable row level security;

create policy "injury_recovery_state_select_own" on injury_recovery_state
  for select using (auth.uid() = user_id);

-- No client-facing write policy on purpose -- report-injury and
-- record-injury-checkin (service-role) are the only writers.
