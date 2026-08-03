-- Sport Goal Programs launch catalog: 4 sports x 8 goals, authored from
-- docs/features/sport-goal-content-blueprint.md and
-- docs/research/2026-08-03-sport-goal-evidence.md. Every sport seeds
-- status='internal' -- the feature ships DARK behind the kill switch;
-- flipping to 'live' is a later manual UPDATE after S&C review (O-10) and
-- safety sign-off (O-2 scope), never part of this migration. Target
-- tables carry gain ranges, horizons, dose, and source notes verbatim
-- from the evidence doc; padel numbers keep their [EST]/[PROXY] markers
-- and must survive expert review before going live. expert_reviewed=false
-- on every goal. All goal_exercise ids were verified against
-- 20260731091000_seed_exercise_library.sql (id convention: spaces ->
-- underscores, apostrophes stripped, slashes -> underscores, e.g.
-- "Farmer's Walk" -> Farmers_Walk, "90/90 Hamstring" -> 90_90_Hamstring);
-- all 72 distinct blueprint names resolved, zero substitutions needed.
-- Blueprint [drill] items (wall-rally practice, dead-hang intervals,
-- hollow-body hold, crow progressions, pull-up negatives, ...) are
-- concept-drills: described by goal_work_concept text, no goal_exercise
-- row, per the blueprint's option-1 gap decision.

-- Sports: all internal (dark launch). variant reserved, null for v1.
insert into sports (id, name, variant, status) values
  ('volleyball', 'Volleyball', null, 'internal'),
  ('hot_yoga',   'Hot Yoga',   null, 'internal'),
  ('climbing',   'Climbing',   null, 'internal'),
  ('padel',      'Padel',      null, 'internal');

-- Goals. noise_band is in the goal's own unit; null where the evidence
-- gives only a relative MDC or none (details in each target_table).
insert into sport_goals (id, sport_id, key, name, kind, unit, measurement_protocol, noise_band, target_table, expert_reviewed, author) values
  ('volleyball_standing_vertical_jump', 'volleyball', 'standing_vertical_jump', 'Standing vertical jump', 'metric', 'cm',
   'Stand side-on to a wall with chalked fingertips. Mark your standing reach, then jump and mark the highest touch; the jump is touch minus reach. Best of 3 attempts. Same wall and same warm-up state every test.',
   2,
   '{
     "unit": "cm",
     "bands": {
       "novice":       {"gain_low": 3, "gain_high": 6, "gain_pct": "8-15", "horizon_weeks_low": 10, "horizon_weeks_high": 12},
       "intermediate": {"gain_low": 2, "gain_high": 4, "horizon_weeks_low": 8, "horizon_weeks_high": 12},
       "advanced":     {"gain_low": 1, "gain_high": 2, "horizon_weeks_low": 8, "horizon_weeks_high": 12}
     },
     "dose": "2-3 sessions/wk, >=20 sessions, 50-100 contacts/session",
     "retest_interval_weeks": "6, then 8-12",
     "source_note": "Markovic 2007 (Br J Sports Med, 26 studies: CMJ +8.7%); Saez de Villarreal 2009 (JSCR, 56 studies: mean +3.9 cm, ES 0.84); MDC ~2 cm; use average of jump trials, not best (Claudino 2017)"
   }'::jsonb,
   false, 'Soma internal — pending S&C review (O-10)'),

  ('volleyball_wall_pass_60s', 'volleyball', 'wall_pass_60s', 'Wall-pass count in 60 seconds', 'metric', 'count',
   'Mark a line on a wall at 3.4 m (Brady-style wall volley, r=0.83 reliability). Pass the ball against the wall above the line for 60 seconds; count legal passes. Same wall, same ball, same distance every test.',
   5,
   '{
     "unit": "count",
     "bands": {
       "novice":       {"start_range": "5-15", "target_range": "25-40", "rel_gain_pct": "10-20", "horizon_weeks_low": 8, "horizon_weeks_high": 12},
       "intermediate": {"rel_gain_pct": "5-10", "horizon_weeks_low": 8, "horizon_weeks_high": 12},
       "advanced":     {"rel_gain_pct": "2-5", "note": "approximately noise", "horizon_weeks_low": 8, "horizon_weeks_high": 12}
     },
     "dose": ">=4-6 wk, 2-3 sessions/wk, 100-300 quality reps",
     "retest_interval_weeks": "4-6, identical protocol",
     "source_note": "Brady wall-volley r=0.83; Lin 2022 (Appl Sci, volleyball receiving: +9.3% at 4 wk, control +4.3%); ~4-5 pts of first-test gain is familiarization -- noise_band set to 5 counts from that figure"
   }'::jsonb,
   false, 'Soma internal — pending S&C review (O-10)'),

  ('hot_yoga_forward_fold', 'hot_yoga', 'forward_fold', 'Forward-fold depth', 'metric', 'cm',
   'Sit with legs straight and bare feet flat against a wall. Reach forward slowly along a ruler on the floor; record fingertip position relative to your toes (+ past, - short). Same ruler setup and same time of day every test.',
   3,
   '{
     "unit": "cm",
     "bands": {
       "novice":       {"gain_low": 4, "gain_high": 6, "horizon_weeks_low": 4, "horizon_weeks_high": 8},
       "intermediate": {"gain_low": 2, "gain_high": 4, "horizon_weeks_low": 4, "horizon_weeks_high": 8},
       "advanced":     {"gain_low": 0, "gain_high": 2, "horizon_weeks_low": 4, "horizon_weeks_high": 8}
     },
     "dose": "3-5 days/wk; first change 2-4 wk, bulk of gains by 6-8 wk",
     "retest_interval_weeks": "4, then 8",
     "source_note": "Konrad 2024 (J Sport Health Sci, 77 studies: stretching ES -1.0; volume/intensity/frequency do NOT moderate gains); MDC ~3-4 cm; novice band is the v1 launch target (+4-6 cm / 4-8 wk), int/adv from the core evidence table (+2-4 / 0-2 cm)"
   }'::jsonb,
   false, 'Soma internal — pending S&C review (O-10)'),

  ('hot_yoga_crow_pose', 'hot_yoga', 'crow_pose', 'Crow pose', 'milestone', 'seconds',
   'From a squat, place hands flat shoulder-width apart, knees on upper arms, shift weight forward. Milestone ladder: never tried -> both feet lift -> 3-second hold -> timed hold in seconds. Film from the side to verify.',
   null,
   '{
     "unit": "milestone",
     "ladder": ["never_tried", "feet_lift", "hold_3s", "hold_seconds"],
     "bands": {
       "novice": {"milestone": "first lift-off", "horizon_weeks_low": 2, "horizon_weeks_high": 8}
     },
     "source_note": "Milestone ladder per launch catalog; no numeric promise -- honest time estimate exists only for first lift-off (2-8 wk); hold-seconds targets for later bands pending S&C review"
   }'::jsonb,
   false, 'Soma internal — pending S&C review (O-10)'),

  ('climbing_dead_hang', 'climbing', 'dead_hang', 'Max dead hang', 'metric', 'seconds',
   'Hang from a pull-up bar (never a fingerboard) with a comfortable overhand grip, feet off the floor; time from full hang to release. One max trial after a standard warm-up.',
   null,
   '{
     "unit": "seconds",
     "bands": {
       "novice":       {"gain_pct_low": 40, "gain_pct_high": 80, "horizon_weeks_low": 4, "horizon_weeks_high": 8, "measure": "hang time on a bar"},
       "intermediate": {"gain_pct_low": 10, "gain_pct_high": 20, "horizon_weeks_low": 8, "horizon_weeks_high": 10, "measure": "added load"},
       "advanced":     {"gain_pct_low": 5, "gain_pct_high": 10, "horizon_weeks_low": 8, "horizon_weeks_high": 10, "measure": "added load"}
     },
     "dose": "2 sessions/wk; >=80% intensity for max strength; hangs never on consecutive days",
     "retest_interval_weeks": "4-6",
     "mdc": "~6-9% of load (relative -- absolute noise_band left null)",
     "source_note": "Hermans 2022 (Front Sports Act Living, 10-wk RCT: +17% peak force, control unchanged); bar only -- hangboard/finger goals are gated out of v1 until the climbing-age gate exists"
   }'::jsonb,
   false, 'Soma internal — pending S&C review (O-10)'),

  ('climbing_max_pullups', 'climbing', 'max_pullups', 'Max strict pull-ups', 'metric', 'reps',
   'From a full dead hang, pull to chin over the bar with no kip; count strict reps. If band-assisted, log the band and use the identical band for the whole block.',
   null,
   '{
     "unit": "reps",
     "bands": {
       "novice": {"start": 0, "target_low": 3, "target_high": 5, "horizon_weeks_low": 8, "horizon_weeks_high": 12}
     },
     "retest_interval_weeks": "4-6",
     "source_note": "v1 launch target (0 -> 3-5 strict reps / 8-12 wk); no published MDC -- resolution is 1 strict rep; intermediate/advanced bands pending S&C review"
   }'::jsonb,
   false, 'Soma internal — pending S&C review (O-10)'),

  ('padel_wall_rally_60s', 'padel', 'wall_rally_60s', 'Wall-rally count in 60 seconds', 'metric', 'count',
   'Tape a line on a wall at 0.88 m (net height) and a restraint line 2.5-3 m from the wall. Rally against the wall above the line for 60 seconds from behind the restraint line; take the median of 3 trials.',
   null,
   '{
     "unit": "count",
     "bands": {
       "novice": {"gain_pct_low": 40, "gain_pct_high": 70, "horizon_weeks_low": 8, "horizon_weeks_high": 12, "marker": "[EST]"}
     },
     "retest_interval_weeks": "4-6, identical protocol",
     "source_note": "[EST] app-estimated -- padel-specific intervention magnitudes are missing; the test descends from the Dyer backboard test, validity r=.92 vs match play [PROXY-tennis]; must survive expert review (O-10) before live"
   }'::jsonb,
   false, 'Soma internal — pending S&C review (O-10)'),

  ('padel_lateral_shuttle', 'padel', 'lateral_shuttle', 'Lateral shuttle time', 'metric', 'seconds',
   'Set two tape lines 4 m apart on a non-slip surface. Side-shuffle 6 x 4 m as fast as possible; time it from 60 fps video, frame-counted start to finish.',
   0.29,
   '{
     "unit": "seconds",
     "bands": {
       "novice": {"time_drop_pct_low": 3, "time_drop_pct_high": 8, "horizon_weeks_low": 8, "horizon_weeks_high": 12, "marker": "[PROXY]"}
     },
     "retest_interval_weeks": "4-6",
     "source_note": "[PROXY] gain magnitude proxied from tennis/racquet data; the test itself is padel-validated (Attia 2020, COD test lineage: ICC .96, SEM 1.35%, MDC95 0.29 s -- the noise band); must survive expert review (O-10) before live"
   }'::jsonb,
   false, 'Soma internal — pending S&C review (O-10)');

-- Goal-exercise mappings: verified library exercises only; [drill] items
-- live in goal_work_concept text instead.
insert into goal_exercise (goal_id, exercise_id, role) values
  -- Volleyball: standing vertical jump
  ('volleyball_standing_vertical_jump', 'Barbell_Squat', 'strength'),
  ('volleyball_standing_vertical_jump', 'Goblet_Squat', 'strength'),
  ('volleyball_standing_vertical_jump', 'Romanian_Deadlift', 'strength'),
  ('volleyball_standing_vertical_jump', 'Barbell_Hip_Thrust', 'strength'),
  ('volleyball_standing_vertical_jump', 'Standing_Calf_Raises', 'strength'),
  ('volleyball_standing_vertical_jump', 'Split_Squat_with_Dumbbells', 'strength'),
  ('volleyball_standing_vertical_jump', 'Bodyweight_Squat', 'strength'),
  ('volleyball_standing_vertical_jump', 'Glute_Kickback', 'strength'),
  ('volleyball_standing_vertical_jump', 'Knee_Tuck_Jump', 'plyo'),
  ('volleyball_standing_vertical_jump', 'Standing_Long_Jump', 'plyo'),
  ('volleyball_standing_vertical_jump', 'Front_Box_Jump', 'plyo'),
  ('volleyball_standing_vertical_jump', 'Freehand_Jump_Squat', 'plyo'),
  ('volleyball_standing_vertical_jump', 'Depth_Jump_Leap', 'plyo'),
  ('volleyball_standing_vertical_jump', 'Hurdle_Hops', 'plyo'),
  ('volleyball_standing_vertical_jump', 'Box_Jump_Multiple_Response', 'plyo'),
  ('volleyball_standing_vertical_jump', 'Single_Leg_Push-off', 'plyo'),
  ('volleyball_standing_vertical_jump', 'Rocket_Jump', 'plyo'),
  ('volleyball_standing_vertical_jump', 'Bench_Jump', 'plyo'),
  ('volleyball_standing_vertical_jump', 'Weighted_Jump_Squat', 'plyo'),
  ('volleyball_standing_vertical_jump', 'Standing_Gastrocnemius_Calf_Stretch', 'mobility'),
  ('volleyball_standing_vertical_jump', 'Hamstring_Stretch', 'mobility'),
  ('volleyball_standing_vertical_jump', 'Kneeling_Hip_Flexor', 'mobility'),
  ('volleyball_standing_vertical_jump', 'Ankle_Circles', 'mobility'),
  -- Volleyball: wall-pass count
  ('volleyball_wall_pass_60s', 'External_Rotation_with_Band', 'prehab'),
  ('volleyball_wall_pass_60s', 'Band_Pull_Apart', 'prehab'),
  ('volleyball_wall_pass_60s', 'Face_Pull', 'prehab'),
  ('volleyball_wall_pass_60s', 'Russian_Twist', 'strength'),
  ('volleyball_wall_pass_60s', 'Side_to_Side_Box_Shuffle', 'technique'),
  ('volleyball_wall_pass_60s', 'Shoulder_Circles', 'mobility'),
  ('volleyball_wall_pass_60s', 'Behind_Head_Chest_Stretch', 'mobility'),
  -- Hot yoga: forward fold
  ('hot_yoga_forward_fold', 'Standing_Toe_Touches', 'mobility'),
  ('hot_yoga_forward_fold', 'Seated_Floor_Hamstring_Stretch', 'mobility'),
  ('hot_yoga_forward_fold', 'Leg-Up_Hamstring_Stretch', 'mobility'),
  ('hot_yoga_forward_fold', '90_90_Hamstring', 'mobility'),
  ('hot_yoga_forward_fold', 'Kneeling_Hip_Flexor', 'mobility'),
  ('hot_yoga_forward_fold', 'Childs_Pose', 'mobility'),
  ('hot_yoga_forward_fold', 'Cat_Stretch', 'mobility'),
  ('hot_yoga_forward_fold', 'The_Straddle', 'mobility'),
  ('hot_yoga_forward_fold', 'Runners_Stretch', 'mobility'),
  ('hot_yoga_forward_fold', 'Worlds_Greatest_Stretch', 'mobility'),
  ('hot_yoga_forward_fold', 'Romanian_Deadlift', 'strength'),
  ('hot_yoga_forward_fold', 'Good_Morning', 'strength'),
  -- Hot yoga: crow pose. Frog_Hops is 'plyometrics' in the library but
  -- the blueprint uses it as the hip-opener cluster -> role mobility.
  ('hot_yoga_crow_pose', 'Wrist_Circles', 'mobility'),
  ('hot_yoga_crow_pose', 'Kneeling_Forearm_Stretch', 'mobility'),
  ('hot_yoga_crow_pose', 'Frog_Hops', 'mobility'),
  ('hot_yoga_crow_pose', 'Seated_Palm-Up_Barbell_Wrist_Curl', 'prehab'),
  ('hot_yoga_crow_pose', 'Plank', 'strength'),
  ('hot_yoga_crow_pose', 'Dead_Bug', 'strength'),
  ('hot_yoga_crow_pose', 'Sit_Squats', 'strength'),
  -- Climbing: max dead hang
  ('climbing_dead_hang', 'Scapular_Pull-Up', 'strength'),
  ('climbing_dead_hang', 'Pullups', 'strength'),
  ('climbing_dead_hang', 'Band_Assisted_Pull-Up', 'strength'),
  ('climbing_dead_hang', 'Farmers_Walk', 'strength'),
  ('climbing_dead_hang', 'Plate_Pinch', 'strength'),
  ('climbing_dead_hang', 'Wrist_Roller', 'strength'),
  ('climbing_dead_hang', 'Inverted_Row', 'strength'),
  ('climbing_dead_hang', 'Hammer_Curls', 'strength'),
  ('climbing_dead_hang', 'External_Rotation_with_Band', 'prehab'),
  ('climbing_dead_hang', 'Dumbbell_Lying_Pronation', 'prehab'),
  ('climbing_dead_hang', 'Dumbbell_Lying_Supination', 'prehab'),
  ('climbing_dead_hang', 'Kneeling_Forearm_Stretch', 'mobility'),
  ('climbing_dead_hang', 'Shoulder_Circles', 'mobility'),
  -- Climbing: max strict pull-ups
  ('climbing_max_pullups', 'Band_Assisted_Pull-Up', 'strength'),
  ('climbing_max_pullups', 'Chin-Up', 'strength'),
  ('climbing_max_pullups', 'Bent_Over_Barbell_Row', 'strength'),
  ('climbing_max_pullups', 'Inverted_Row', 'strength'),
  ('climbing_max_pullups', 'One-Arm_Dumbbell_Row', 'strength'),
  ('climbing_max_pullups', 'Scapular_Pull-Up', 'strength'),
  ('climbing_max_pullups', 'Plank', 'strength'),
  ('climbing_max_pullups', 'Hanging_Pike', 'strength'),
  ('climbing_max_pullups', 'Band_Pull_Apart', 'prehab'),
  ('climbing_max_pullups', 'Face_Pull', 'prehab'),
  -- Padel: wall rally
  ('padel_wall_rally_60s', 'Side_to_Side_Box_Shuffle', 'technique'),
  ('padel_wall_rally_60s', 'Carioca_Quick_Step', 'technique'),
  ('padel_wall_rally_60s', 'Dumbbell_Lying_Pronation', 'prehab'),
  ('padel_wall_rally_60s', 'Dumbbell_Lying_Supination', 'prehab'),
  ('padel_wall_rally_60s', 'Seated_Palms-Down_Barbell_Wrist_Curl', 'prehab'),
  ('padel_wall_rally_60s', 'Band_Pull_Apart', 'prehab'),
  ('padel_wall_rally_60s', 'Wrist_Circles', 'mobility'),
  -- Padel: lateral shuttle
  ('padel_lateral_shuttle', 'Lateral_Bound', 'plyo'),
  ('padel_lateral_shuttle', 'Lateral_Cone_Hops', 'plyo'),
  ('padel_lateral_shuttle', 'Side_Hop-Sprint', 'plyo'),
  ('padel_lateral_shuttle', 'Single-Leg_Lateral_Hop', 'plyo'),
  ('padel_lateral_shuttle', 'Split_Squat_with_Dumbbells', 'strength'),
  ('padel_lateral_shuttle', 'Barbell_Side_Split_Squat', 'strength'),
  ('padel_lateral_shuttle', 'Standing_Calf_Raises', 'strength'),
  ('padel_lateral_shuttle', 'Crossover_Reverse_Lunge', 'strength'),
  ('padel_lateral_shuttle', 'Side_to_Side_Box_Shuffle', 'technique'),
  ('padel_lateral_shuttle', 'Carioca_Quick_Step', 'technique'),
  ('padel_lateral_shuttle', 'Monster_Walk', 'prehab'),
  ('padel_lateral_shuttle', 'Standing_Soleus_And_Achilles_Stretch', 'mobility'),
  ('padel_lateral_shuttle', 'Ankle_Circles', 'mobility'),
  ('padel_lateral_shuttle', 'Adductor', 'mobility');

-- Work concepts: the blueprint's category x phase matrices. phase null =
-- same content across the block; safety caps ride in dose_notes.
insert into goal_work_concept (id, goal_id, category, phase, focus, modality, duration_minutes_min, duration_minutes_max, dose_notes, description) values
  -- Volleyball: standing vertical jump (Foundation -> Build -> Peak)
  ('vj_push_hard_foundation', 'volleyball_standing_vertical_jump', 'push_hard', 'foundation',
   'Strength base + intro plyometrics', 'strength+plyo', 15, 20,
   'Intro plyo <=60 ground contacts/session; NSCA novice caps 80-100 contacts/session, 48-72 h between plyo days',
   'Barbell Squat or Goblet Squat, Romanian Deadlift, Barbell Hip Thrust, Standing Calf Raises; introduce Knee Tuck Jump and Standing Long Jump at low volume.'),
  ('vj_push_hard_build', 'volleyball_standing_vertical_jump', 'push_hard', 'build',
   'Plyometric focus, strength maintained', 'plyo+strength', 15, 20,
   '80-100 ground contacts/session, 48-72 h between plyo days; Depth Jump Leap gated to intermediate+ experience',
   'Front Box Jump, Freehand Jump Squat, Hurdle Hops (Depth Jump Leap for intermediate+ only); keep squat/hinge strength work in maintenance doses.'),
  ('vj_push_hard_peak', 'volleyball_standing_vertical_jump', 'push_hard', 'peak',
   'Reactive jumps, tapered volume', 'plyo', 15, 20,
   'Taper contact volume, keep intensity; 48-72 h between plyo days',
   'Depth Jump Leap, Box Jump (Multiple Response), Single Leg Push-off; low volume, maximal intent every rep.'),
  ('vj_moderate_foundation', 'volleyball_standing_vertical_jump', 'moderate', 'foundation',
   'Strength only, no plyometrics', 'strength', 10, 15,
   'No jump contacts on moderate days in foundation',
   'Squat/hinge/calf strength plus Split Squat with Dumbbells.'),
  ('vj_moderate_build', 'volleyball_standing_vertical_jump', 'moderate', 'build',
   'Low-dose plyo + strength', 'plyo+strength', 10, 15,
   '<=40 ground contacts/session',
   'Rocket Jump and Bench Jump at low volume, plus maintained strength work.'),
  ('vj_moderate_peak', 'volleyball_standing_vertical_jump', 'moderate', 'peak',
   'Light ballistic technique', 'plyo', 10, 15,
   'Light loads only; quality over volume',
   'Weighted Jump Squat light, plus technique jumps.'),
  ('vj_light', 'volleyball_standing_vertical_jump', 'light', null,
   'Landing mechanics + easy lower-body work', 'technique+mobility', 10, 15,
   'No maximal jumping on light days',
   'Jump-landing mechanics drill (stick landings), Bodyweight Squat, Glute Kickback, ankle/calf mobility with Standing Gastrocnemius Calf Stretch.'),
  ('vj_rest', 'volleyball_standing_vertical_jump', 'rest', null,
   'Optional 5-minute mobility', 'mobility', 5, 5,
   'Optional -- or nothing',
   'Hamstring Stretch, Kneeling Hip Flexor, Ankle Circles.'),

  -- Volleyball: wall-pass count
  ('wp_push_hard', 'volleyball_wall_pass_60s', 'push_hard', null,
   'Wall-pass volume blocks + footwork', 'skill', 15, 20,
   'Volume by phase: 3x60 s (foundation) -> 5x90 s (build); 100-300 quality reps across the week',
   'Wall-pass practice blocks (concept drill) with split-step footwork drill and Side to Side Box Shuffle; shoulder prehab: External Rotation with Band, Band Pull Apart, Face Pull; core: Russian Twist.'),
  ('wp_moderate', 'volleyball_wall_pass_60s', 'moderate', null,
   'Wall-pass practice + supporting work', 'skill', 10, 15,
   'Volume by phase: 3x60 s (foundation) -> 5x90 s (build)',
   'Wall-pass practice blocks (concept drill), footwork drill, shoulder prehab and core as on push-hard days at reduced volume.'),
  ('wp_light', 'volleyball_wall_pass_60s', 'light', null,
   'Short technique sets, accuracy over count', 'skill', 8, 12,
   'Accuracy over count; shoulder prehab only, no volume work',
   'Short wall-pass technique sets (concept drill) plus shoulder prehab.'),
  ('wp_rest', 'volleyball_wall_pass_60s', 'rest', null,
   'Optional shoulder mobility', 'mobility', 5, 5,
   'Optional -- or nothing',
   'Shoulder Circles, Behind Head Chest Stretch.'),

  -- Hot yoga: forward fold (Release -> Deepen render as client copy)
  ('ff_push_hard', 'hot_yoga_forward_fold', 'push_hard', null,
   'Mobility block + loaded end-range', 'mobility+strength', 10, 15,
   'Dose stays modest by design -- volume/intensity do NOT scale ROM gains (Konrad 2024); consistency is the lever',
   'Full stretch sequence plus light Romanian Deadlift, light Good Morning, and PNF cycles (concept drill).'),
  ('ff_moderate', 'hot_yoga_forward_fold', 'moderate', null,
   'Daily-capable mobility block', 'mobility', 10, 15,
   'Consistency over intensity (Konrad 2024)',
   'Standing Toe Touches, Seated Floor Hamstring Stretch, Leg-Up Hamstring Stretch, 90/90 Hamstring, Kneeling Hip Flexor, Child''s Pose, Cat Stretch, The Straddle, Runner''s Stretch, World''s Greatest Stretch.'),
  ('ff_light', 'hot_yoga_forward_fold', 'light', null,
   'Daily-capable mobility block', 'mobility', 10, 15,
   'Flexibility work is fully light-day compatible',
   'Same daily-capable stretch sequence as moderate days.'),
  ('ff_rest', 'hot_yoga_forward_fold', 'rest', null,
   'Shortened 5-minute sequence', 'mobility', 5, 5,
   'Flexibility is ideal rest-day content; still optional',
   'Short hamstring/hip subset of the daily sequence.'),

  -- Hot yoga: crow pose (Wrists & core -> Lift-off render as client copy)
  ('crow_push_hard', 'hot_yoga_crow_pose', 'push_hard', null,
   'Wrist prep, core, hips, crow progressions', 'skill+strength', 15, 20,
   'Attempt crow fresh, early in the session; stop before wrist fatigue',
   'Wrist Circles, Kneeling Forearm Stretch, light Seated Palm-Up Barbell Wrist Curl; core: Plank, Dead Bug, hollow-body hold (concept drill); hips: Frog Hops stretch, Sit Squats; crow progressions -- knees-on-arms lifts, one-foot lifts (concept drill).'),
  ('crow_moderate', 'hot_yoga_crow_pose', 'moderate', null,
   'Wrist prep, core, hips, crow progressions', 'skill+strength', 10, 15,
   'Same cluster as push-hard at reduced volume; stop before wrist fatigue',
   'Wrist prep, core and hip work, plus a short crow-progression set (concept drill).'),
  ('crow_light', 'hot_yoga_crow_pose', 'light', null,
   'Wrist mobility + short fresh crow attempts', 'skill+mobility', 8, 12,
   'Low volume, attempts only while fresh',
   'Wrist mobility plus short crow attempts (concept drill).'),
  ('crow_rest', 'hot_yoga_crow_pose', 'rest', null,
   'Optional wrist/hip mobility', 'mobility', 5, 5,
   'Optional -- or nothing',
   'Wrist Circles, Kneeling Forearm Stretch, easy hip openers.'),

  -- Climbing: max dead hang (Grip base -> Density render as client copy)
  ('dh_push_hard', 'climbing_dead_hang', 'push_hard', null,
   'Sub-max hang intervals + pull/grip strength', 'strength', 15, 20,
   'Hangs on a bar, never a fingerboard; hangs never on consecutive days; 2 hang sessions/wk',
   'Sub-max dead-hang intervals (concept drill); Scapular Pull-Up, Pullups or Band Assisted Pull-Up, Farmer''s Walk, Plate Pinch, Wrist Roller.'),
  ('dh_moderate', 'climbing_dead_hang', 'moderate', null,
   'Shorter hang density + upper-back support', 'strength', 10, 15,
   'Shorter hangs; hangs never on consecutive days',
   'Hang density sets (concept drill); Inverted Row, External Rotation with Band, Hammer Curls.'),
  ('dh_light', 'climbing_dead_hang', 'light', null,
   'Forearm rotation + mobility, no hangs', 'prehab+mobility', 8, 12,
   'No hangs on light days -- protects the no-consecutive-hang-days rule',
   'Dumbbell Lying Pronation, Dumbbell Lying Supination, Kneeling Forearm Stretch, Shoulder Circles.'),
  ('dh_rest', 'climbing_dead_hang', 'rest', null,
   'Optional forearm/shoulder mobility', 'mobility', 5, 5,
   'Optional -- or nothing',
   'Easy forearm and shoulder mobility.'),

  -- Climbing: max strict pull-ups (Assisted volume -> Strict strength)
  ('pu_push_hard', 'climbing_max_pullups', 'push_hard', null,
   'Assisted ladders + strict pulling strength', 'strength', 15, 20,
   null,
   'Band Assisted Pull-Up ladders, pull-up negatives (concept drill), Chin-Up, Bent Over Barbell Row.'),
  ('pu_moderate', 'climbing_max_pullups', 'moderate', null,
   'Rows, scapular control, core', 'strength', 10, 15,
   'Hanging Pike gated to intermediate+ experience',
   'Inverted Row, One-Arm Dumbbell Row, Scapular Pull-Up; core: Plank, Hanging Pike (intermediate+).'),
  ('pu_light', 'climbing_max_pullups', 'light', null,
   'Upper-back prehab + grip mobility', 'prehab+mobility', 8, 12,
   null,
   'Band Pull Apart, Face Pull, grip mobility.'),
  ('pu_rest', 'climbing_max_pullups', 'rest', null,
   'Optional mobility', 'mobility', 5, 5,
   'Optional -- or nothing',
   'Easy upper-body mobility.'),

  -- Padel: wall rally (Contact -> Rally -> Pressure render as client copy)
  ('wr_push_hard', 'padel_wall_rally_60s', 'push_hard', null,
   'Wall-rally blocks + footwork + elbow micro-block', 'skill', 15, 20,
   '<=3 wall sessions/wk total, ramp <=10-20%/wk (elbow ECRB rule); elbow pain reported -> rally volume drops, eccentrics stay (Tyler 2010)',
   'Wall-rally blocks (concept drill); footwork: Side to Side Box Shuffle, Carioca Quick Step; mandatory elbow micro-block: Dumbbell Lying Pronation, Dumbbell Lying Supination, light Seated Palms-Down Barbell Wrist Curl with eccentric emphasis, Wrist Circles.'),
  ('wr_moderate', 'padel_wall_rally_60s', 'moderate', null,
   'Wall-rally blocks + footwork + elbow micro-block', 'skill', 10, 15,
   '<=3 wall sessions/wk total, ramp <=10-20%/wk (elbow ECRB rule); elbow pain reported -> rally volume drops, eccentrics stay',
   'Same cluster as push-hard days at reduced rally volume; the elbow micro-block is never skipped.'),
  ('wr_light', 'padel_wall_rally_60s', 'light', null,
   'Short contact-control sets + elbow eccentrics', 'skill+prehab', 8, 12,
   'Accuracy focus; wall volume still counts toward the <=3 wall sessions/wk cap',
   'Short contact-control sets (concept drill), elbow eccentrics, Band Pull Apart.'),
  ('wr_rest', 'padel_wall_rally_60s', 'rest', null,
   'Optional forearm/shoulder mobility', 'mobility', 5, 5,
   'Optional -- or nothing',
   'Easy forearm and shoulder mobility.'),

  -- Padel: lateral shuttle (Strength -> Speed render as client copy)
  ('ls_push_hard', 'padel_lateral_shuttle', 'push_hard', null,
   'Lateral plyometrics + lower-body strength', 'plyo+strength', 15, 20,
   'NSCA plyo caps 80-100 contacts/session, 48-72 h between plyo days; non-slip surface; calf work is Achilles care for the 35+ demographic',
   'Lateral Bound, Lateral Cone Hops, Side Hop-Sprint, Single-Leg Lateral Hop; strength: Split Squat with Dumbbells, Barbell Side Split Squat, Standing Calf Raises.'),
  ('ls_moderate', 'padel_lateral_shuttle', 'moderate', null,
   'Sub-maximal lateral footwork', 'technique+strength', 10, 15,
   'Sub-maximal only; non-slip surface',
   'Side to Side Box Shuffle, Carioca Quick Step, Monster Walk, Crossover Reverse Lunge.'),
  ('ls_light', 'padel_lateral_shuttle', 'light', null,
   'Low-intensity footwork + lower-leg/hip mobility', 'technique+mobility', 8, 12,
   null,
   'Low-intensity footwork patterns (concept drill), Standing Soleus And Achilles Stretch, Ankle Circles, Adductor stretch.'),
  ('ls_rest', 'padel_lateral_shuttle', 'rest', null,
   'Optional lower-leg mobility', 'mobility', 5, 5,
   'Optional -- or nothing',
   'Easy calf, ankle and hip mobility.');

-- Pregnancy gate values (evidence doc, ACOG-derived). Safe with
-- modifications: wall pass, forward fold, bar hangs, pull-ups. Paused:
-- plyo/jump, crow (fall risk), racquet play and ballistic lateral work.
update sport_goals set pregnancy_safe = true where id in (
  'volleyball_wall_pass_60s',
  'hot_yoga_forward_fold',
  'climbing_dead_hang',
  'climbing_max_pullups'
);
