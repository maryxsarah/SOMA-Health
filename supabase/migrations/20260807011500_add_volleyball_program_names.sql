-- First named-program identities (v1 slice, volleyball jump goal only --
-- see docs/bug-log.md O-14). Same evidence bands, just given a name.
update sport_goals
set target_table = jsonb_set(target_table, '{bands,novice,program_name}', '"Foundation Jump Block"')
where id = 'volleyball_standing_vertical_jump';

update sport_goals
set target_table = jsonb_set(target_table, '{bands,intermediate,program_name}', '"Builder Jump Block"')
where id = 'volleyball_standing_vertical_jump';

update sport_goals
set target_table = jsonb_set(target_table, '{bands,advanced,program_name}', '"Power Jump Block"')
where id = 'volleyball_standing_vertical_jump';
