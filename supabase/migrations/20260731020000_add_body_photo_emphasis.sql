-- Silent output of analyze-body-photo (AI vision comparison of the user's
-- stored goal/current body photos) -- a secondary signal feeding
-- generate-workout-plan's prompt, never shown to the user directly.
-- NULL = never analyzed; '{}' = analyzed, no confident emphasis; non-empty
-- = confident GoalTag raw values. The two source_*_path columns make
-- re-analysis idempotent (skip the OpenAI call if both photos are
-- unchanged since the last run).
alter table users
  add column body_photo_emphasis_tags text[],
  add column body_photo_emphasis_source_goal_path text,
  add column body_photo_emphasis_source_current_path text,
  add column body_photo_emphasis_updated_at timestamptz;
