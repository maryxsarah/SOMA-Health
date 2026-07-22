-- Fields collected by the expanded onboarding survey. `goals` (existing
-- column) already stores the user's chosen primary goal as a one-element
-- array using the same GoalTag vocabulary as the Profile screen -- no
-- separate "primary goal" column needed, they merge naturally.

alter table users
  add column sex text check (sex in ('male', 'female', 'other')),
  add column workouts_per_week text check (workouts_per_week in ('zero_to_two', 'three_to_five', 'six_plus')),
  add column date_of_birth date,
  add column referral_source text,
  add column weight_kg numeric,
  add column desired_weight_kg numeric,
  add column works_with_trainer boolean,
  add column goal_pace text check (goal_pace in ('slow', 'recommended', 'fast')),
  add column blockers text[] not null default '{}',
  add column diet_type text,
  add column accomplishment_goal text,
  add column marketing_opt_in boolean not null default false;

-- Existing RLS policies (auth.uid() = id) already cover these new columns.
