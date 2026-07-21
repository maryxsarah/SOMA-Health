-- Adds user profile fields (contact email, goals, equipment/access, and
-- injuries) so daily recommendations can be personalized. Values are
-- stored as text arrays matching the Swift-side GoalTag/EquipmentTag/
-- InjuryTag enum raw values (e.g. 'build_strength', 'resistance_bands',
-- 'knee') -- no DB-level check constraint on array contents for V1
-- simplicity; the app is the single writer of these fields.

alter table users
  add column contact_email text,
  add column goals text[] not null default '{}',
  add column equipment text[] not null default '{}',
  add column injury_tags text[] not null default '{}',
  add column injury_notes text;

-- Injury-based intensity cap, mirroring sleep_cap_applied: tracks whether
-- generate-recommendation downgraded today's category because the user
-- has an active injury noted, independent of whether the sleep cap also
-- fired.
alter table daily_recommendation
  add column injury_cap_applied boolean not null default false;

-- Existing RLS policies (auth.uid() = id / user_id) already cover these
-- new columns; no policy changes needed.
