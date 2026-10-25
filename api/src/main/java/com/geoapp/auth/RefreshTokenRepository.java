package com.geoapp.auth;

import java.time.Instant;
import java.time.OffsetDateTime;
import java.time.ZoneOffset;
import java.util.Optional;
import java.util.UUID;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Repository;

@Repository
public class RefreshTokenRepository {

    private final JdbcClient jdbc;

    public RefreshTokenRepository(JdbcClient jdbc) {
        this.jdbc = jdbc;
    }

    public void insert(UUID userId, String tokenHash, Instant expiresAt) {
        jdbc.sql("INSERT INTO refresh_tokens (user_id, token_hash, expires_at) VALUES (:user, :hash, :exp)")
                .param("user", userId)
                .param("hash", tokenHash)
                .param("exp", OffsetDateTime.ofInstant(expiresAt, ZoneOffset.UTC))
                .update();
    }

    /** Marks a valid token as used and returns its owner; a second call with the same token returns empty. */
    public Optional<UUID> consume(String tokenHash) {
        return jdbc.sql("""
                        UPDATE refresh_tokens SET revoked = true
                        WHERE token_hash = :hash AND revoked = false AND expires_at > now()
                        RETURNING user_id""")
                .param("hash", tokenHash)
                .query(UUID.class).optional();
    }
}
