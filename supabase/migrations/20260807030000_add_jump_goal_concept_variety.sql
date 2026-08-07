-- Rotation variety for the volleyball vertical-jump goal (O-14 follow-up).
-- decideGoalWork already rotates deterministically by date among every
-- eligible goal_work_concept row for a (category, phase) pair
-- (goalWork.ts:181-208, rotateByDate at line 140) -- today there is exactly
-- one row per pair, so nothing to rotate among, which is why the same 2-3
-- named exercises recurred every session for weeks at a time (reported
-- against the demo video: "Front Box Jump" three times in one plan, then
-- again day after day). This migration adds a second row per non-rest
-- (category, phase) pair so the mechanism has something to alternate.
--
-- No new research and no new exercises: every "_b" row only recombines
-- exercises ALREADY in this goal's goal_exercise mapping
-- (20260803130000_seed_sport_goal_catalog.sql:151-173), keeping the same
-- intensity tier and the same dose_notes/safety caps as its "_a" sibling --
-- only which named movements show up on a given day changes, the volume
-- and gating rules (Depth Jump Leap intermediate+ only, plyo contact caps)
-- do not.

insert into goal_work_concept (id, goal_id, category, phase, focus, modality, duration_minutes_min, duration_minutes_max, dose_notes, description) values

  ('vj_push_hard_foundation_b', 'volleyball_standing_vertical_jump', 'push_hard', 'foundation',
   'Strength base + intro plyometrics', 'strength+plyo', 15, 20,
   'Intro plyo <=60 ground contacts/session; NSCA novice caps 80-100 contacts/session, 48-72 h between plyo days',
   'Romanian Deadlift, Split Squat with Dumbbells, Standing Calf Raises, Glute Kickback; introduce Standing Long Jump and Knee Tuck Jump at low volume.'),

  ('vj_push_hard_build_b', 'volleyball_standing_vertical_jump', 'push_hard', 'build',
   'Plyometric focus, strength maintained', 'plyo+strength', 15, 20,
   '80-100 ground contacts/session, 48-72 h between plyo days; Depth Jump Leap gated to intermediate+ experience',
   'Box Jump (Multiple Response), Standing Long Jump, Knee Tuck Jump (Depth Jump Leap for intermediate+ only); keep squat/hinge strength work in maintenance doses.'),

  ('vj_push_hard_peak_b', 'volleyball_standing_vertical_jump', 'push_hard', 'peak',
   'Reactive jumps, tapered volume', 'plyo', 15, 20,
   'Taper contact volume, keep intensity; 48-72 h between plyo days',
   'Hurdle Hops, Rocket Jump, Single Leg Push-off; low volume, maximal intent every rep.'),

  ('vj_moderate_foundation_b', 'volleyball_standing_vertical_jump', 'moderate', 'foundation',
   'Strength only, no plyometrics', 'strength', 10, 15,
   'No jump contacts on moderate days in foundation',
   'Bodyweight Squat, Romanian Deadlift, Glute Kickback, Standing Calf Raises.'),

  ('vj_moderate_build_b', 'volleyball_standing_vertical_jump', 'moderate', 'build',
   'Low-dose plyo + strength', 'plyo+strength', 10, 15,
   '<=40 ground contacts/session',
   'Knee Tuck Jump and Standing Long Jump at low volume, plus maintained strength work.'),

  ('vj_moderate_peak_b', 'volleyball_standing_vertical_jump', 'moderate', 'peak',
   'Light ballistic technique', 'plyo', 10, 15,
   'Light loads only; quality over volume',
   'Front Box Jump light technique work, plus Bodyweight Squat.'),

  ('vj_light_b', 'volleyball_standing_vertical_jump', 'light', null,
   'Landing mechanics + easy lower-body work', 'technique+mobility', 10, 15,
   'No maximal jumping on light days',
   'Jump-landing mechanics drill (stick landings), Glute Kickback, Standing Calf Raises light, Kneeling Hip Flexor and Ankle Circles mobility.');
