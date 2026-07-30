-- In-app feedback / bug reports: backs the shake gesture and the Profile
-- "Send feedback" card. Client-writable via RLS (no service-role Edge
-- Function needed) -- this is user-entered content, same category as
-- workout_log. The device/app columns are captured client-side at submit
-- time so a report is diagnosable without a reply: version, build, OS,
-- and hardware are the first four questions triage would otherwise ask.
-- Read path is the Supabase dashboard (service role); users can also
-- read back their own reports, which keeps a future "my reports" screen
-- possible without a migration.

create table user_feedback (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references users(id) on delete cascade,
  type text not null check (type in ('bug', 'idea', 'other')),
  message text not null check (char_length(message) between 1 and 4000),
  app_version text not null,
  build text not null,
  os_version text not null,
  device_model text not null,
  created_at timestamptz not null default now()
);

alter table user_feedback enable row level security;

create policy "user_feedback_select_own" on user_feedback
  for select using (auth.uid() = user_id);

create policy "user_feedback_insert_own" on user_feedback
  for insert with check (auth.uid() = user_id);
