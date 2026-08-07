-- "What would you like to accomplish?" is becoming multi-select (tester
-- feedback: forcing a single pick when several genuinely apply), matching
-- the pattern `goals` already uses. Existing single values are preserved
-- as one-element arrays rather than dropped.
alter table users rename column accomplishment_goal to accomplishment_goals;
alter table users alter column accomplishment_goals drop default;
alter table users
  alter column accomplishment_goals type text[]
  using case when accomplishment_goals is null then '{}'::text[] else array[accomplishment_goals] end;
alter table users alter column accomplishment_goals set default '{}';
alter table users alter column accomplishment_goals set not null;
