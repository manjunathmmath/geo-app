package com.geoapp.users;

import java.time.OffsetDateTime;
import java.util.List;
import java.util.Optional;
import java.util.UUID;
import org.springframework.jdbc.core.RowMapper;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Repository;

@Repository
public class UserRepository {

    private static final RowMapper<User> MAPPER = (rs, i) -> new User(
            rs.getObject("id", UUID.class),
            rs.getString("email"),
            rs.getString("phone"),
            rs.getString("password_hash"),
            Role.valueOf(rs.getString("role")),
            UserStatus.valueOf(rs.getString("status")),
            rs.getObject("created_at", OffsetDateTime.class).toInstant());

    private final JdbcClient jdbc;

    public UserRepository(JdbcClient jdbc) {
        this.jdbc = jdbc;
    }

    public Optional<User> findById(UUID id) {
        return jdbc.sql("SELECT * FROM users WHERE id = :id").param("id", id).query(MAPPER).optional();
    }

    public Optional<User> findByEmail(String email) {
        return jdbc.sql("SELECT * FROM users WHERE lower(email) = lower(:email)")
                .param("email", email).query(MAPPER).optional();
    }

    /** Throws DuplicateKeyException when the email is already registered. */
    public User insert(String email, String passwordHash, Role role) {
        return jdbc.sql("INSERT INTO users (email, password_hash, role) VALUES (:email, :hash, :role) RETURNING *")
                .param("email", email)
                .param("hash", passwordHash)
                .param("role", role.name())
                .query(MAPPER).single();
    }

    public List<User> list(int limit, int offset) {
        return jdbc.sql("SELECT * FROM users ORDER BY created_at DESC LIMIT :limit OFFSET :offset")
                .param("limit", limit).param("offset", offset).query(MAPPER).list();
    }

    /** Null arguments leave that column unchanged. */
    public int update(UUID id, UserStatus status, Role role) {
        return jdbc.sql("""
                        UPDATE users
                        SET status = COALESCE(CAST(:status AS varchar), status),
                            role   = COALESCE(CAST(:role AS varchar), role)
                        WHERE id = :id""")
                .param("id", id)
                .param("status", status == null ? null : status.name())
                .param("role", role == null ? null : role.name())
                .update();
    }
}
