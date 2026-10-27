-- A small preview image for photo and video posts, so grids and lists do not have to load the full file.
ALTER TABLE posts ADD COLUMN thumb_path text;
