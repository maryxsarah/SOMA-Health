-- avatars bucket (20260806020000) had no size/type limits, unlike every
-- other upload bucket in the app.
update storage.buckets
set file_size_limit = 5242880, -- 5MB
    allowed_mime_types = array['image/jpeg']
where id = 'avatars';
