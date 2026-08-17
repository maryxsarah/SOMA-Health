-- Account deletion (App Review 5.1.1(v)): auth.admin.deleteUser must be
-- able to cascade through the whole app schema. public.users referenced
-- auth.users with the default NO ACTION, which blocks deleting the auth
-- row while the profile exists; every app table already cascades off
-- public.users (see 20260728010000), and the two sport-goal tables that
-- reference auth.users directly were created with cascade from day one.
-- The delete-account edge function also deletes the public.users row
-- explicitly before deleteUser (belt and braces), but the FK should not
-- be the thing standing between a user and erasure.
alter table users drop constraint if exists users_id_fkey;
alter table users add constraint users_id_fkey
  foreign key (id) references auth.users(id) on delete cascade;
