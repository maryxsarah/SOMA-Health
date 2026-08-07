-- Manual food-intake logging -- lets the nutrition-targets bars (see
-- nutrition_targets, computed in analyze-body-photo) actually fill
-- through the day instead of only ever showing a static target. Same
-- shape as workout_log: user-entered content, no derived/safety logic
-- involved, client-writable directly via RLS.
--
-- `source` defaults to 'manual' (today's only entry path -- a quick
-- number-entry form, no photo/AI parsing) but is forward-compatible with
-- a future real meal-scan feature writing 'photo' rows into this same
-- table without a schema change, per nutritionTargets.ts's own comment
-- about meal_logs being "the natural connection point."
create table meal_log (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references users(id) on delete cascade,
  date date not null,
  label text,
  calories integer not null,
  protein_g integer not null,
  carbs_g integer,
  fat_g integer,
  source text not null default 'manual' check (source in ('manual', 'photo')),
  logged_at timestamptz not null default now()
);

alter table meal_log enable row level security;

create policy "meal_log_select_own" on meal_log
  for select using (auth.uid() = user_id);

create policy "meal_log_insert_own" on meal_log
  for insert with check (auth.uid() = user_id);

create policy "meal_log_delete_own" on meal_log
  for delete using (auth.uid() = user_id);
