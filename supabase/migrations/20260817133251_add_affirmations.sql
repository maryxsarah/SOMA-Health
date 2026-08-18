-- Affirmations (Soma Refresh Turn 16) -- one kind AI line a day plus a
-- personal list the reminder rotation draws from.
--
-- daily_affirmation: one server-generated row per (user, date), written
-- only by the generate-affirmation edge function (service role). The
-- client reads it via RLS and may UPDATE the text in place (16b's "Edit"
-- rewrites today's line) -- but never inserts, so generation itself stays
-- behind the function's daily limit. `language` is a real column (not
-- stashed inside a jsonb like ai_workout_plan's signatures) because it's
-- the row's only cache-validity input.
--
-- user_affirmations: the user's own kept/written lines (16b's "Keep" and
-- "Write your own..."), fully client-owned via RLS. in_rotation toggles a
-- line in or out of the notification rotation without deleting it.
--
-- ai_generation_log.source gains 'affirmation' -- same widen-before-first-
-- use lesson as BUG-92. Deliberately NOT added to WORKOUT_GENERATION_SOURCES,
-- so affirmation generations never eat the workout quota.

alter table ai_generation_log drop constraint ai_generation_log_source_check;
alter table ai_generation_log add constraint ai_generation_log_source_check
  check (source in ('suggestion', 'gym_photo', 'addon_suggestion', 'meal_text_estimate', 'meal_rating', 'goal_assignment_parse', 'meal_recommendation', 'exercise_translation', 'affirmation'));

-- `edited` marks a line the user rewrote in place (16b "Edit") -- when a
-- replacement generates, an edited line is auto-promoted into
-- user_affirmations ("your words are never discarded"); untouched lines
-- just age out of the 7-day Recent window.
create table if not exists daily_affirmation (
  user_id uuid references users(id) on delete cascade,
  date date not null,
  text text not null,
  language text not null default 'en',
  edited boolean not null default false,
  generated_at timestamptz not null default now(),
  primary key (user_id, date)
);

alter table daily_affirmation enable row level security;

create policy "daily_affirmation_select_own" on daily_affirmation
  for select using (auth.uid() = user_id);

-- Edit-in-place only -- inserts stay server-side (service role).
create policy "daily_affirmation_update_own" on daily_affirmation
  for update using (auth.uid() = user_id);

create table if not exists user_affirmations (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references users(id) on delete cascade,
  text text not null,
  source text not null check (source in ('generated', 'custom')),
  in_rotation boolean not null default true,
  created_at timestamptz not null default now()
);

create index user_affirmations_user_idx on user_affirmations (user_id, created_at desc);

alter table user_affirmations enable row level security;

create policy "user_affirmations_select_own" on user_affirmations
  for select using (auth.uid() = user_id);

create policy "user_affirmations_insert_own" on user_affirmations
  for insert with check (auth.uid() = user_id);

create policy "user_affirmations_update_own" on user_affirmations
  for update using (auth.uid() = user_id);

create policy "user_affirmations_delete_own" on user_affirmations
  for delete using (auth.uid() = user_id);
