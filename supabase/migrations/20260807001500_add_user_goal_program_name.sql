-- Named-program identity, snapshotted at creation like target_low/high --
-- the client never re-reads the live catalog after a goal is created.
-- if not exists: the column is already live on remote (this file was one
-- of the 20260807000000 timestamp-collision twins the migration history
-- skipped), so replaying it must be a no-op rather than an error.
alter table user_goal add column if not exists program_name text;
