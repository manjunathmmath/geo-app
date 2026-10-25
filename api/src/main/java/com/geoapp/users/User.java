package com.geoapp.users;

import java.time.Instant;
import java.util.UUID;

public record User(
        UUID id,
        String email,
        String phone,
        String passwordHash,
        Role role,
        UserStatus status,
        Instant createdAt) {}
