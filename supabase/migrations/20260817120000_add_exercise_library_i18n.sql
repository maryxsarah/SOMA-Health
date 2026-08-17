-- Cached AI translations of exercise_library's English-only name +
-- how-to instructions, one row per (exercise, language). Written only by
-- the translate-exercise-guide edge function (service role) on first
-- request for a given pair, then served from here forever -- one Claude
-- call per exercise per language across ALL users, not per view.
create table exercise_library_i18n (
  exercise_id text not null references exercise_library (id) on delete cascade,
  language text not null,
  name text not null,
  instructions text[] not null default '{}',
  created_at timestamptz not null default now(),
  primary key (exercise_id, language)
);

-- Same public-reference-data posture as exercise_library itself: anyone
-- signed in can read, nothing is client-written.
alter table exercise_library_i18n enable row level security;

create policy "exercise_library_i18n_select_all" on exercise_library_i18n
  for select using (true);

-- translate-exercise-guide's rate-limit rows -- same "widen from day one"
-- lesson as BUG-92 (see 20260806090000/20260809040000).
alter table ai_generation_log drop constraint ai_generation_log_source_check;
alter table ai_generation_log add constraint ai_generation_log_source_check
  check (source in ('suggestion', 'gym_photo', 'addon_suggestion', 'meal_text_estimate', 'meal_rating', 'goal_assignment_parse', 'meal_recommendation', 'exercise_translation'));
