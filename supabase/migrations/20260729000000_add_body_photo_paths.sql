-- Nullable storage-path columns (not the image itself) for the optional
-- goal-body/current-body photo feature. Feature is client-side flagged
-- off pending legal review -- see Config.enableBodyPhotoUpload.

alter table users
  add column goal_body_photo_path text,
  add column current_body_photo_path text;
