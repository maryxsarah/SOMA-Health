-- Every per-user table declared `user_id uuid references users(id)` without
-- NOT NULL. RLS (auth.uid() = user_id) blocks a null from any client, but
-- the Edge Functions all run as service_role, which bypasses RLS entirely --
-- so a null user_id was only ever prevented by every call site remembering
-- to pass one. A null row would be invisible to its owner (RLS matches on
-- equality, and `auth.uid() = null` is null, not true) while still counting
-- toward every aggregate: orphaned, unreadable, undeletable through the app.
--
-- Verified before writing this: zero null user_id rows across all seven
-- tables in production, so these all take without a backfill.

alter table ai_workout_plan        alter column user_id set not null;
alter table daily_recommendation   alter column user_id set not null;
alter table daily_snapshot         alter column user_id set not null;
alter table healthkit_workout_sync alter column user_id set not null;
alter table safety_flag_log        alter column user_id set not null;
alter table wearable_tokens        alter column user_id set not null;
alter table workout_log            alter column user_id set not null;
