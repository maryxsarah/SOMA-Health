-- Cache for generate-gym-workout, mirroring what ai_workout_plan does for
-- generate-workout-plan. Without it, every invocation re-called the vision
-- wording model: cheap per call, but unbounded per user per day, and the
-- sibling generation path is explicitly cost-controlled, so the asymmetry
-- was accidental rather than intended.
--
-- Keyed on the equipment signature as well as the date, because the whole
-- point of the feature is that the answer changes when your surroundings
-- change. Re-opening the result for the same setup is a cache hit; taking
-- a fresh photo of a different gym is a miss and regenerates, which is the
-- behaviour users expect from a "retake photo" button.
--
-- The signature is computed server-side from the confirmed equipment list
-- (sorted, joined) so the client cannot influence cache identity.

create table gym_workout_plan (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references users(id) on delete cascade,
  date date not null,
  equipment_signature text not null,
  category text not null,
  plan jsonb not null,
  created_at timestamptz not null default now(),
  unique (user_id, date, equipment_signature)
);

alter table gym_workout_plan enable row level security;

-- Read-only to the owner; all writes go through the service-role client
-- inside the Edge Function, same pattern as ai_workout_plan.
create policy "gym_workout_plan_select_own" on gym_workout_plan
  for select using (auth.uid() = user_id);
