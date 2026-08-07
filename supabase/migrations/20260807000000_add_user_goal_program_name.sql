-- Named-program identity, snapshotted at creation like target_low/high --
-- the client never re-reads the live catalog after a goal is created.
alter table user_goal add column program_name text;
