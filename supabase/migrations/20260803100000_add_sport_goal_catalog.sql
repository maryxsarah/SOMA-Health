-- Sport Goal Programs catalog (spec: docs/features/sport-skill-programs.md).
-- Four reference tables (sports, sport_goals, goal_exercise,
-- goal_work_concept) hold every prescription as data -- the model only
-- words them -- so adding or editing a goal is a migration, not an App
-- Store release. Unlike exercise_library's read-all archetype, reads are
-- filtered by sports.status: that filter IS the feature kill switch.
-- Everything seeds 'internal' (dark), internal testers exercise it in
-- production, and one manual UPDATE flips a sport 'live' -- rollback is
-- the same switch in reverse, no release either way. Catalog writes are
-- service-role only (seed migrations); the only client-writable table here
-- is beta_optins (a deliberate self-service opt-in, see below).

-- Tester roster, secrets archetype (wearable_tokens precedent): RLS on,
-- ZERO policies -- written and read by service role only.
create table internal_testers (
  -- Deliberately not a users.internal_tester flag: users can update their
  -- own users row and could self-grant.
  user_id uuid primary key references auth.users(id) on delete cascade
);

alter table internal_testers enable row level security;

-- RLS applies inside policy subqueries, so a bare exists() against the
-- zero-policy roster would always be empty. security definer bypasses it;
create function is_internal_tester()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  -- Callers only ever learn a boolean about themselves, never the roster.
  select exists (select 1 from internal_testers t where t.user_id = auth.uid());
$$;

-- Beta roster, unlike internal_testers deliberately user-writable: beta is
-- a self-service opt-in from the app's settings, not a staff grant.
create table beta_optins (
  user_id uuid primary key references auth.users(id) on delete cascade
);

alter table beta_optins enable row level security;

create policy "beta_optins_select_own" on beta_optins
  for select using (auth.uid() = user_id);

create policy "beta_optins_insert_own" on beta_optins
  for insert with check (auth.uid() = user_id);

create policy "beta_optins_delete_own" on beta_optins
  for delete using (auth.uid() = user_id);

-- Mirrors is_internal_tester(): security definer so policy subqueries see
-- the row despite RLS; callers only learn a boolean about themselves.
create function is_beta_opted_in()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (select 1 from beta_optins b where b.user_id = auth.uid());
$$;

create table sports (
  id text primary key,
  name text not null,
  -- Reserved for future splits (beach volleyball, bouldering vs rope);
  -- null for the whole v1 catalog.
  variant text,
  status text not null check (status in ('seeded','internal','beta','live')) default 'seeded'
);

alter table sports enable row level security;

-- One visibility rule for sports and every child table: 'seeded' invisible,
-- 'internal' testers only, 'beta' opt-ins (and testers), 'live' everyone.
create function sport_status_visible(status text)
returns boolean
language sql
stable
as $$
  select status = 'live'
    or (status = 'internal' and is_internal_tester())
    or (status = 'beta' and (is_beta_opted_in() or is_internal_tester()));
$$;

-- The kill switch: flipping status needs no app release.
create policy "sports_select_visible" on sports
  for select using (sport_status_visible(status));

create table sport_goals (
  id text primary key,
  sport_id text not null references sports(id),
  key text not null,
  name text not null,
  kind text not null check (kind in ('metric','milestone','qualitative')),
  unit text,
  measurement_protocol text,
  -- Smallest honest change in the goal's unit; below it the app renders
  -- "no change". Null where the evidence gives no absolute MDC.
  noise_band numeric,
  -- Evidence table as data: level bands -> gain range + horizon weeks,
  -- dose, re-test interval, and the source note (spec decision 2).
  target_table jsonb,
  -- Pregnancy hard-pause gate (spec decision 8, ACOG-derived): false =
  -- reporting a pregnancy auto-pauses an active goal on this row.
  pregnancy_safe boolean not null default false,
  expert_reviewed boolean not null default false,
  author text,
  unique (sport_id, key)
);

alter table sport_goals enable row level security;

-- Child visibility = the parent sport's visibility, so the whole subtree
-- follows the one switch.
create policy "sport_goals_select_visible" on sport_goals
  for select using (
    exists (
      select 1 from sports s
      where s.id = sport_goals.sport_id
        and sport_status_visible(s.status)
    )
  );

-- Joins goals to the existing exercise_library so goal-mapped exercises
-- union into the closed vocabulary with real media, no new plumbing.
create table goal_exercise (
  goal_id text not null references sport_goals(id) on delete cascade,
  exercise_id text not null references exercise_library(id),
  role text not null check (role in ('strength','plyo','technique','mobility','prehab')),
  primary key (goal_id, exercise_id)
);

alter table goal_exercise enable row level security;

create policy "goal_exercise_select_visible" on goal_exercise
  for select using (
    exists (
      select 1
      from sport_goals g
      join sports s on s.id = g.sport_id
      where g.id = goal_exercise.goal_id
        and sport_status_visible(s.status)
    )
  );

-- What decideGoalWork selects from: one concept per category (x phase
-- where content differs by phase), mirroring finisherCatalog.ts fields.
create table goal_work_concept (
  id text primary key,
  goal_id text not null references sport_goals(id) on delete cascade,
  category text not null check (category in ('rest','light','moderate','push_hard')),
  -- Null = phase-agnostic (same content all block). Sport-specific phase
  -- display names ("Release/Deepen") are client copy, not data.
  phase text check (phase in ('foundation','build','peak')),
  focus text not null,
  modality text,
  duration_minutes_min integer,
  duration_minutes_max integer,
  -- Carries the safety caps (plyo contacts, wall-session limits, hang
  -- spacing) -- deterministic dose, never model-invented.
  dose_notes text,
  description text
);

create index goal_work_concept_goal_idx on goal_work_concept (goal_id);

alter table goal_work_concept enable row level security;

create policy "goal_work_concept_select_visible" on goal_work_concept
  for select using (
    exists (
      select 1
      from sport_goals g
      join sports s on s.id = g.sport_id
      where g.id = goal_work_concept.goal_id
        and sport_status_visible(s.status)
    )
  );
