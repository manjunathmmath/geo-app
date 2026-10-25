CREATE EXTENSION IF NOT EXISTS postgis;

-- Email and phone are both nullable so phone-OTP accounts can be added later
-- without a schema change; at least one must be present.
CREATE TABLE users (
    id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    email         varchar(254),
    phone         varchar(20),
    password_hash varchar(100),
    role          varchar(10)  NOT NULL CHECK (role IN ('CREATOR', 'ADMIN')),
    status        varchar(10)  NOT NULL DEFAULT 'ACTIVE' CHECK (status IN ('ACTIVE', 'BLOCKED')),
    created_at    timestamptz  NOT NULL DEFAULT now(),
    CONSTRAINT users_identity_chk CHECK (email IS NOT NULL OR phone IS NOT NULL)
);
CREATE UNIQUE INDEX users_email_uq ON users (lower(email)) WHERE email IS NOT NULL;
CREATE UNIQUE INDEX users_phone_uq ON users (phone) WHERE phone IS NOT NULL;

CREATE TABLE refresh_tokens (
    id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id    uuid         NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    token_hash char(64)     NOT NULL UNIQUE,
    expires_at timestamptz  NOT NULL,
    revoked    boolean      NOT NULL DEFAULT false,
    created_at timestamptz  NOT NULL DEFAULT now()
);
CREATE INDEX refresh_tokens_user_idx ON refresh_tokens (user_id);

CREATE TABLE posts (
    id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    author_id     uuid         NOT NULL REFERENCES users (id),
    type          varchar(10)  NOT NULL CHECK (type IN ('IMAGE', 'VIDEO', 'AUDIO')),
    media_path    text         NOT NULL,
    caption       varchar(500),
    location      geography(Point, 4326) NOT NULL,
    accuracy_m    real,
    status        varchar(10)  NOT NULL DEFAULT 'PENDING' CHECK (status IN ('PENDING', 'APPROVED', 'REJECTED')),
    reviewed_by   uuid REFERENCES users (id),
    reviewed_at   timestamptz,
    reject_reason varchar(500),
    created_at    timestamptz  NOT NULL DEFAULT now()
);
-- Only approved posts are ever searched by location.
CREATE INDEX posts_location_approved_idx ON posts USING GIST (location) WHERE status = 'APPROVED';
CREATE INDEX posts_status_created_idx ON posts (status, created_at);
CREATE INDEX posts_author_idx ON posts (author_id, created_at DESC);

CREATE TABLE reports (
    id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    post_id     uuid         NOT NULL REFERENCES posts (id) ON DELETE CASCADE,
    reporter_id uuid         NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    reason      varchar(500) NOT NULL,
    created_at  timestamptz  NOT NULL DEFAULT now(),
    UNIQUE (post_id, reporter_id)
);
