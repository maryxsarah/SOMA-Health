-- Sport Goal Programs user state (spec: docs/features/sport-skill-programs.md,
-- "Data model" + "Goal lifecycle"). user_goal is one row per goal attempt,
-- preset or custom (coach's task), and rows are NEVER deleted: the
-- accumulated completed rows ARE the achievements log, and abandoned rows
-- keep their measurement history for a later restart. The partial unique
-- index enforces the one-active-goal product decision while letting
-- paused/finished goals accumulate freely. goal_measurement_log holds the
-- locked re-test events (baseline x2, checkpoint, final) that back the
-- progress chart across chained blocks. Both follow the workout_log
-- user-entered archetype: direct client RLS writes, no edge function
-- required for reads/writes the user owns.

create table user_goal (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references users(id) on delete cascade,
  -- Null for custom (coach's task) goals; presets point at the catalog.
  goal_id text references sport_goals(id),
  kind text not null check (kind in ('preset','custom')),
  target_kind text not null check (target_kind in ('metric','milestone','qualitative','commitment')),
  status text not null check (status in ('active','completed','paused','abandoned')) default 'active',
  -- 'safety' = hard-conflict auto-pause (frozen ETA, locked re-tests);
  -- 'user' = one-tap postpone. Null unless paused.
  pause_reason text check (pause_reason in ('safety','user')),
  baseline_value numeric,
  -- Non-numeric starting point for milestone/qualitative goals (e.g.
  -- "knees on floor, back rounded") -- charted as the origin label.
  baseline_stage text,
  target_low numeric,
  target_high numeric,
  -- Worded target for qualitative/milestone/commitment goals ("confident
  -- crow pose, 10s hold") -- the honest target when there is no number.
  target_text text,
  -- ETA is always a range; missed sessions slide these dates visibly.
  eta_start date,
  eta_end date,
  -- Visible slip vs the original window, recomputed deterministically at
  -- plan time with its one-line reason. Null when on schedule.
  eta_slip_days integer,
  eta_slip_reason text,
  phase text,
  result_value numeric,
  completed_at timestamptz,
  -- Custom-goal fields: the coach's assignment, stored verbatim and never
  -- rewritten by the app.
  given_text text,
  workout_text text,
  coach_name text,
  duration_weeks integer,
  -- Fixed re-check date for custom goals -- the coach owns pacing, so no
  -- sliding ETA here.
  recheck_date date,
  custom_metric_name text,
  custom_metric_unit text,
  assignment_photo_path text,
  -- Stored safety-conflict acknowledgment ("my coach knows my situation")
  -- from the create-goal keyword pass.
  safety_ack jsonb,
  frequency_per_week integer,
  schedule_rule text check (schedule_rule in ('weekdays','every_other_day','before_court_days','readiness')),
  schedule_days int[],
  court_days int[],
  created_at timestamptz not null default now()
);

-- One active goal per user; paused/completed/abandoned rows do not hold
-- the slot (spec: "Postpone ... does not hold the active slot").
create unique index user_goal_one_active_per_user
  on user_goal (user_id) where status = 'active';

alter table user_goal enable row level security;

create policy "user_goal_select_own" on user_goal
  for select using (auth.uid() = user_id);

create policy "user_goal_insert_own" on user_goal
  for insert with check (auth.uid() = user_id);

create policy "user_goal_update_own" on user_goal
  for update using (auth.uid() = user_id);

-- No delete policy on purpose: rows are never deleted -- completed rows
-- are the achievements log, abandoned rows keep their history.

create table goal_measurement_log (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references users(id) on delete cascade,
  user_goal_id uuid not null references user_goal(id) on delete cascade,
  -- baseline is measured twice in week 1; the confirm attempt becomes
  -- official (eats test-familiarization noise).
  kind text not null check (kind in ('baseline','baseline_confirm','checkpoint','final')),
  value numeric,
  measured_at timestamptz not null default now()
);

create index goal_measurement_log_goal_idx
  on goal_measurement_log (user_goal_id, measured_at);

alter table goal_measurement_log enable row level security;

create policy "goal_measurement_log_select_own" on goal_measurement_log
  for select using (auth.uid() = user_id);

create policy "goal_measurement_log_insert_own" on goal_measurement_log
  for insert with check (auth.uid() = user_id);

-- Append-only: no update/delete policies keeps the re-test history honest
-- (a logged max is a logged max).
