package com.geoapp.security;

import com.geoapp.users.Role;
import java.util.UUID;

/** The authenticated principal placed in the security context by {@link JwtAuthFilter}. */
public record AuthUser(UUID id, String email, Role role) {}
