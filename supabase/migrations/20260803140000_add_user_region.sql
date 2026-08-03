-- Where the user trains: country (ISO region code, e.g. "SE") and city
-- (free text). Feeds region-scoped content like the "Where to practice"
-- links planned for sport goals v1.1. No check constraints: the client is
-- the single writer, same trust model as the users tag arrays.
alter table users
  add column country text,
  add column city text;
