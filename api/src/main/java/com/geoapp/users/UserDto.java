package com.geoapp.users;

import java.time.Instant;
import java.util.UUID;

/** What the API returns about a user; never includes the password hash. */
public record UserDto(UUID id, String email, String phone, Role role, UserStatus status, Instant createdAt) {

    public static UserDto from(User u) {
        return new UserDto(u.id(), u.email(), u.phone(), u.role(), u.status(), u.createdAt());
    }
}
