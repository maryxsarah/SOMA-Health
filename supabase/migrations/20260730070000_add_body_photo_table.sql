-- Real history of goal/current body photos, additive alongside the
-- existing users.goal_body_photo_path/current_body_photo_path columns
-- (which continue to work unmodified as a "latest photo" pointer -- every
-- upload updates both). Client-writable via RLS directly, same category as
-- workout_log: user-entered content, no derived/safety logic involved.

create table body_photo (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references users(id) on delete cascade,
  kind text not null check (kind in ('goal', 'current')),
  storage_path text not null,
  taken_at timestamptz not null default now()
);

alter table body_photo enable row level security;

create policy "body_photo_select_own" on body_photo
  for select using (auth.uid() = user_id);

create policy "body_photo_insert_own" on body_photo
  for insert with check (auth.uid() = user_id);

create policy "body_photo_delete_own" on body_photo
  for delete using (auth.uid() = user_id);
