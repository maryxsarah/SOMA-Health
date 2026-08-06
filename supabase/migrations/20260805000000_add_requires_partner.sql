-- Many people train alone; some exercise_library rows (Free Exercise DB)
-- genuinely require a second person with no reasonable solo substitute --
-- mostly partner-assisted PNF stretches (one person holds/resists while
-- the other stretches) and a few strength drills where a partner hands
-- off or spots a weight into position. Flagging these lets
-- exerciseLibraryMatch.ts exclude them from the default candidate pool
-- the same way it already excludes exercises the user lacks equipment
-- for.
--
-- This list was built by hand, not a keyword heuristic -- an earlier
-- substring-based pass ("contains partner, unless it also contains an
-- escape phrase") produced false positives on rows like Sit-Up and
-- Russian Twist, which both already offer a built-in solo alternative
-- ("feet under something that will not move") using different wording
-- than any fixed escape-phrase list would reliably catch. Every row
-- below was read in full; a row that offers ANY stated solo alternative
-- (a wall, bracing under something stable, an optional band/box assist)
-- is deliberately NOT on this list, even if its instructions mention
-- "partner" somewhere.
alter table exercise_library add column requires_partner boolean not null default false;

update exercise_library set requires_partner = true where name in (
  'Adductor/Groin',
  'Behind Head Chest Stretch',
  'Lying Bent Leg Groin',
  'Lying Crossover',
  'Lying Glute',
  'Lying Hamstring',
  'Lying Prone Quadriceps',
  'Overhead Lat',
  'Overhead Triceps',
  'Prone Manual Hamstring',
  'Seated Biceps',
  'Seated Front Deltoid',
  'Seated Glute',
  'Seated Hamstring',
  'Medicine Ball Full Twist',
  'One Arm Floor Press',
  'Return Push from Stance',
  'Standing Towel Triceps Extension',
  'Weighted Bench Dip'
);
