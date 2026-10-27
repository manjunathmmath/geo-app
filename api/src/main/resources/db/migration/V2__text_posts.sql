-- Text posts: a post can now be words only. Media posts keep their file and optional caption.
ALTER TABLE posts ALTER COLUMN media_path DROP NOT NULL;
ALTER TABLE posts ADD COLUMN body varchar(1000);

ALTER TABLE posts DROP CONSTRAINT posts_type_check;
ALTER TABLE posts ADD CONSTRAINT posts_type_check CHECK (type IN ('IMAGE', 'VIDEO', 'AUDIO', 'TEXT'));

-- A text post has text and no file; every other post has a file.
ALTER TABLE posts ADD CONSTRAINT posts_content_chk CHECK (
    (type = 'TEXT' AND body IS NOT NULL AND media_path IS NULL)
    OR (type <> 'TEXT' AND media_path IS NOT NULL));
