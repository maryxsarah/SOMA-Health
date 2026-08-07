-- The bulk upload (supabase storage cp -r) preserved the source directory
-- name, landing files at exercise-media/exercises/{id}/N.jpg rather than
-- exercise-media/{id}/N.jpg as the seed migration assumed -- fix the
-- stored paths to match where the files actually are.
update exercise_library
set image_paths = (
  select array_agg('exercises/' || path)
  from unnest(image_paths) as path
);
