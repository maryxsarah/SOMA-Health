-- Second named-program identity slice (O-14): the 7 goals left over after
-- the volleyball jump goal (20260807010000) -- same mechanism, same
-- Foundation/Builder/<tier> naming convention, no new columns. Tier name
-- for the top band reflects what the evidence table says actually changes
-- there (e.g. climbing's advanced band trains via added load, not more
-- reps -- "Load Hang Block", not "Power Hang Block").

-- Volleyball: wall-pass count (novice/intermediate/advanced)
update sport_goals
set target_table = jsonb_set(target_table, '{bands,novice,program_name}', '"Foundation Pass Block"')
where id = 'volleyball_wall_pass_60s';

update sport_goals
set target_table = jsonb_set(target_table, '{bands,intermediate,program_name}', '"Builder Pass Block"')
where id = 'volleyball_wall_pass_60s';

update sport_goals
set target_table = jsonb_set(target_table, '{bands,advanced,program_name}', '"Precision Pass Block"')
where id = 'volleyball_wall_pass_60s';

-- Hot yoga: forward-fold depth (novice/intermediate/advanced)
update sport_goals
set target_table = jsonb_set(target_table, '{bands,novice,program_name}', '"Foundation Fold Block"')
where id = 'hot_yoga_forward_fold';

update sport_goals
set target_table = jsonb_set(target_table, '{bands,intermediate,program_name}', '"Builder Fold Block"')
where id = 'hot_yoga_forward_fold';

update sport_goals
set target_table = jsonb_set(target_table, '{bands,advanced,program_name}', '"Deep Fold Block"')
where id = 'hot_yoga_forward_fold';

-- Hot yoga: crow pose (novice band only -- milestone ladder)
update sport_goals
set target_table = jsonb_set(target_table, '{bands,novice,program_name}', '"Foundation Crow Block"')
where id = 'hot_yoga_crow_pose';

-- Climbing: max dead hang (novice/intermediate/advanced -- advanced trains
-- via added load per its target_table "measure" field, not more seconds)
update sport_goals
set target_table = jsonb_set(target_table, '{bands,novice,program_name}', '"Foundation Hang Block"')
where id = 'climbing_dead_hang';

update sport_goals
set target_table = jsonb_set(target_table, '{bands,intermediate,program_name}', '"Builder Hang Block"')
where id = 'climbing_dead_hang';

update sport_goals
set target_table = jsonb_set(target_table, '{bands,advanced,program_name}', '"Load Hang Block"')
where id = 'climbing_dead_hang';

-- Climbing: max strict pull-ups (novice band only)
update sport_goals
set target_table = jsonb_set(target_table, '{bands,novice,program_name}', '"Foundation Pull-Up Block"')
where id = 'climbing_max_pullups';

-- Padel: wall-rally count (novice band only)
update sport_goals
set target_table = jsonb_set(target_table, '{bands,novice,program_name}', '"Foundation Rally Block"')
where id = 'padel_wall_rally_60s';

-- Padel: lateral shuttle time (novice band only)
update sport_goals
set target_table = jsonb_set(target_table, '{bands,novice,program_name}', '"Foundation Shuttle Block"')
where id = 'padel_lateral_shuttle';
