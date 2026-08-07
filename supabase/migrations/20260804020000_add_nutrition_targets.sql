-- Deterministic, formula-based daily nutrition targets -- see
-- _shared/nutritionTargets.ts. NOT AI-guessed: recomputed by
-- analyze-body-photo whenever training_emphasis changes, or by anything
-- else later that has a reason to (e.g. a future weight/height edit).
-- One row per user, upserted -- not a history table, unlike body_photo:
-- only "today's target" is ever meaningful, there's no point comparing
-- past targets the way progress photos are compared.
create table nutrition_targets (
  user_id uuid primary key references users(id) on delete cascade,
  daily_calories integer not null,
  daily_protein_g integer not null,
  daily_carbs_g integer not null,
  daily_fat_g integer not null,
  computed_at timestamptz not null default now(),
  -- What inputs/formula produced this, for debugging -- e.g.
  -- "mifflin_st_jeor:cut:activity=moderate". Never shown to the user.
  basis text not null
);

alter table nutrition_targets enable row level security;

create policy "nutrition_targets_select_own" on nutrition_targets
  for select using (auth.uid() = user_id);

-- Inserts/updates happen only via the service-role key from
-- analyze-body-photo, same as daily_recommendation -- no client
-- insert/update policy.
