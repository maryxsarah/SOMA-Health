-- Feedback spec item 6: weekly anchor session becomes a list (up to 5),
-- not a single name/days pair -- real feedback: users with a weekly
-- schedule (gym class Tuesdays, league Saturdays) almost always have more
-- than one recurring commitment, and only the single-anchor shape existed.
--
-- anchor_sessions: jsonb array, each element {id, name, days, timeOfDay}.
-- `days` reuses the exact same weekday convention (0=Sun..6=Sat, JS
-- getUTCDay) the old anchor_session_days/user_goal.schedule_days already
-- used. `timeOfDay` is optional ("morning"/"evening"/"HH:mm" or absent).
--
-- Backfill preserves any existing single anchor as a one-element array
-- (synthesizing an id, since the old shape never had one) before the old
-- columns are dropped -- no user-visible data loss.
alter table users add column anchor_sessions jsonb not null default '[]'::jsonb;

update users
set anchor_sessions = jsonb_build_array(
  jsonb_build_object(
    'id', gen_random_uuid()::text,
    'name', anchor_session_name,
    'days', to_jsonb(anchor_session_days)
  )
)
where anchor_session_name is not null and trim(anchor_session_name) <> '';

alter table users drop column anchor_session_name;
alter table users drop column anchor_session_days;
