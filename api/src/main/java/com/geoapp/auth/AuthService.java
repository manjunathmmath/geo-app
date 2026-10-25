package com.geoapp.auth;

import com.geoapp.auth.AuthDtos.AuthResponse;
import com.geoapp.common.ApiException;
import com.geoapp.config.AppProperties;
import com.geoapp.security.JwtService;
import com.geoapp.users.Role;
import com.geoapp.users.User;
import com.geoapp.users.UserDto;
import com.geoapp.users.UserRepository;
import com.geoapp.users.UserStatus;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.security.SecureRandom;
import java.time.Duration;
import java.time.Instant;
import java.util.Base64;
import java.util.HexFormat;
import org.springframework.dao.DuplicateKeyException;
import org.springframework.http.HttpStatus;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Service;

@Service
public class AuthService {

    private final UserRepository users;
    private final RefreshTokenRepository refreshTokens;
    private final JwtService jwt;
    private final PasswordEncoder encoder;
    private final Duration refreshTtl;
    private final SecureRandom random = new SecureRandom();

    public AuthService(UserRepository users, RefreshTokenRepository refreshTokens, JwtService jwt,
                       PasswordEncoder encoder, AppProperties props) {
        this.users = users;
        this.refreshTokens = refreshTokens;
        this.jwt = jwt;
        this.encoder = encoder;
        this.refreshTtl = props.jwt().refreshTtl();
    }

    public AuthResponse register(String email, String password) {
        try {
            User user = users.insert(normalise(email), encoder.encode(password), Role.CREATOR);
            return issue(user);
        } catch (DuplicateKeyException e) {
            throw new ApiException(HttpStatus.CONFLICT, "Email is already registered");
        }
    }

    public AuthResponse login(String email, String password) {
        User user = users.findByEmail(normalise(email))
                .filter(u -> u.passwordHash() != null && encoder.matches(password, u.passwordHash()))
                .orElseThrow(() -> new ApiException(HttpStatus.UNAUTHORIZED, "Invalid email or password"));
        if (user.status() == UserStatus.BLOCKED) {
            throw new ApiException(HttpStatus.FORBIDDEN, "Account is blocked");
        }
        return issue(user);
    }

    /** Rotates the refresh token: the presented one stops working as soon as a new pair is issued. */
    public AuthResponse refresh(String refreshToken) {
        var userId = refreshTokens.consume(sha256(refreshToken))
                .orElseThrow(() -> new ApiException(HttpStatus.UNAUTHORIZED, "Invalid refresh token"));
        User user = users.findById(userId)
                .filter(u -> u.status() == UserStatus.ACTIVE)
                .orElseThrow(() -> new ApiException(HttpStatus.UNAUTHORIZED, "Invalid refresh token"));
        return issue(user);
    }

    public void logout(String refreshToken) {
        refreshTokens.consume(sha256(refreshToken));
    }

    private AuthResponse issue(User user) {
        byte[] raw = new byte[32];
        random.nextBytes(raw);
        String refresh = Base64.getUrlEncoder().withoutPadding().encodeToString(raw);
        refreshTokens.insert(user.id(), sha256(refresh), Instant.now().plus(refreshTtl));
        return new AuthResponse(jwt.createAccessToken(user), refresh, jwt.accessTtlSeconds(), UserDto.from(user));
    }

    private static String normalise(String email) {
        return email.trim().toLowerCase();
    }

    private static String sha256(String value) {
        try {
            byte[] digest = MessageDigest.getInstance("SHA-256").digest(value.getBytes(StandardCharsets.UTF_8));
            return HexFormat.of().formatHex(digest);
        } catch (NoSuchAlgorithmException e) {
            throw new IllegalStateException(e);
        }
    }
}
