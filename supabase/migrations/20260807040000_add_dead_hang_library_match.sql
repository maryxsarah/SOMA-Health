-- Partial fix for the "no dead hang in the library" gap flagged in
-- docs/features/sport-goal-content-blueprint.md's library coverage audit
-- (climbing_dead_hang's actual test movement has always been a text-only
-- "sub-max dead-hang intervals (concept drill)" -- no library exercise,
-- no photo). Re-searched the seeded Free Exercise DB
-- (20260731091000_seed_exercise_library.sql) directly rather than
-- re-running the blueprint's original audit, and found one real,
-- already-photographed match the original pass didn't map:
-- 'One_Handed_Hang' -- a one-handed bar hang, feet-assisted, category
-- 'stretching' but functionally a grip/lat hang-tolerance exercise.
--
-- This is a supporting addition, not a replacement: it's feet-on-the-
-- ground and one-handed, so it's not the two-handed max-effort test
-- protocol itself (that stays a concept-drill, since the test's exact
-- protocol -- "on a bar, never a fingerboard" -- needs free text, not a
-- library row). It gives the user one real photo of the general hang
-- position and grip while training. Checked the same dataset for
-- crow-pose and hollow-body matches too -- nothing close enough to map
-- honestly (Handstand_Push-Ups and Downward_Facing_Balance were the
-- nearest hits and neither is the actual movement pattern) -- those gaps
-- stand as documented, not silently left unmapped.

insert into goal_exercise (goal_id, exercise_id, role) values
  ('climbing_dead_hang', 'One_Handed_Hang', 'strength');
