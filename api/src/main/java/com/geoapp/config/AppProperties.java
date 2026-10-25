package com.geoapp.config;

import java.time.Duration;
import java.util.List;
import org.springframework.boot.context.properties.ConfigurationProperties;

@ConfigurationProperties(prefix = "app")
public record AppProperties(
        Jwt jwt,
        Storage storage,
        Geo geo,
        List<String> corsOrigins,
        BootstrapAdmin bootstrapAdmin) {

    public record Jwt(String secret, Duration accessTtl, Duration refreshTtl) {}

    public record Storage(String dir) {}

    public record Geo(double defaultRadiusM, double maxRadiusM, double maxAccuracyM) {}

    public record BootstrapAdmin(String email, String password) {}
}
