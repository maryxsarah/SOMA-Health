-- Soma V1 schema
-- Tables are exactly as specified, plus one added constraint (noted inline)
-- and RLS policies restricting every row to its owning auth user.

create table users (
  id uuid primary key references auth.users(id),
  wake_time_pref time not null default '07:00',
  onboarding_complete boolean not null default false,
  created_at timestamptz not null default now()
);

create table wearable_tokens (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references users(id) on delete cascade,
  provider text not null check (provider in ('whoop','oura')),
  access_token text not null,
  refresh_token text,
  expires_at timestamptz,
  created_at timestamptz not null default now()
);

-- Added (not in the original spec): required so store-wearable-token can
-- upsert on reconnect instead of accumulating duplicate rows per provider.
alter table wearable_tokens
  add constraint wearable_tokens_user_provider_unique unique (user_id, provider);

create table daily_snapshot (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references users(id) on delete cascade,
  date date not null,
  source text not null check (source in ('healthkit','whoop','oura')),
  recovery_score numeric,      -- Whoop Recovery %, 0-100
  readiness_score numeric,     -- Oura Readiness score, 0-100
  sleep_hours numeric,
  hrv_ms numeric,
  resting_hr numeric,
  created_at timestamptz not null default now(),
  unique (user_id, date, source)
);

create table daily_recommendation (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references users(id) on delete cascade,
  date date not null,
  category text not null check (category in ('rest','light','moderate','push_hard')),
  message text not null,
  created_at timestamptz not null default now(),
  unique (user_id, date)
);

-- Row Level Security ----------------------------------------------------

alter table users enable row level security;

create policy "users_select_own" on users
  for select using (auth.uid() = id);

create policy "users_insert_own" on users
  for insert with check (auth.uid() = id);

create policy "users_update_own" on users
  for update using (auth.uid() = id);

-- wearable_tokens: RLS is enabled but intentionally has NO client-facing
-- policies. Access tokens/refresh tokens are written and read only by
-- Edge Functions using the service-role key, which bypasses RLS entirely.
-- The app never needs to read raw tokens back; it tracks "connected" state
-- locally right after a successful OAuth round trip.
alter table wearable_tokens enable row level security;

alter table daily_snapshot enable row level security;

create policy "daily_snapshot_select_own" on daily_snapshot
  for select using (auth.uid() = user_id);

-- Inserts/updates to daily_snapshot happen only via the service-role
-- client inside generate-recommendation; no client-facing write policy.

alter table daily_recommendation enable row level security;

create policy "daily_recommendation_select_own" on daily_recommendation
  for select using (auth.uid() = user_id);

-- Inserts/updates to daily_recommendation happen only via the
-- service-role client inside generate-recommendation; no client-facing
-- write policy. The select policy above is what lets HomeView check
-- "does today's row exist" with a plain PostgREST read.
