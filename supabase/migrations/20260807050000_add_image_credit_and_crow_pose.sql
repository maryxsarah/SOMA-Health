-- Closes the hot_yoga_crow_pose library-photo gap for real (O-14 follow-up
-- to 20260807040000, which only found a partial match for climbing's dead
-- hang). The Free Exercise DB import has no crow-pose photo and never will
-- -- it's a fixed public-domain snapshot, not a live feed -- so this is the
-- first exercise_library row sourced from a different, attribution-required
-- license instead. Vetted directly (not guessed): most "yoga pose dataset"
-- results circulating for ML use are unlicensed scrapes (spot-checked one --
-- images traced straight back to pocketyoga.com, a commercial app, with no
-- license at all) and were rejected. This row's photo is individually
-- verified on Wikimedia Commons: CC BY 3.0 (commercial use allowed,
-- attribution required, no share-alike obligation), photographer Kennguru,
-- subject Nina Mel, https://commons.wikimedia.org/wiki/File:Kakasana_Yoga-Asana_Nina-Mel_(cropped,_light_background).jpg
--
-- hollow-body hold got the same real search and came up empty -- no
-- cleanly-licensed photo found anywhere checked (stock-photo sites only,
-- all rights-managed). That gap stands undisturbed; still a real
-- media-sourcing project for that one specifically.

alter table exercise_library add column image_credit text;

insert into exercise_library (id, name, force, level, mechanic, equipment, primary_muscles, secondary_muscles, instructions, category, image_paths, image_credit) values
  ('Crow_Pose_Hold', 'Crow Pose Hold', 'push', 'intermediate', 'isolation', 'body only', '{"abdominals"}', '{"forearms","shoulders"}',
   '{"From a squat, place your hands flat on the floor shoulder-width apart, fingers spread.","Bend your elbows slightly and rest your knees or shins against the backs of your upper arms.","Shift your weight forward onto your hands, engage your core, and lift your feet off the floor.","Keep your gaze slightly forward, not straight down, to help balance. Hold, then lower with control."}',
   'stretching', '{"exercises/Crow_Pose_Hold/0.jpg"}', 'Photo: Kennguru (Nina Mel), Wikimedia Commons, CC BY 3.0');

insert into goal_exercise (goal_id, exercise_id, role) values
  ('hot_yoga_crow_pose', 'Crow_Pose_Hold', 'technique');
