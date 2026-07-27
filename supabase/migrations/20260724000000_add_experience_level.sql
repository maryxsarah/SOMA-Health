-- Training experience level -- feeds AI workout plan generation (block
-- count/complexity, superset usage, rest periods) so a newbie and an
-- advanced lifter get meaningfully different structure for the same
-- category/day, not just the same template with different numbers.

alter table users
  add column experience_level text check (experience_level in ('newbie', 'moderate', 'advanced'));

-- Existing RLS policy (auth.uid() = id) already covers this column; no
-- policy changes needed.
