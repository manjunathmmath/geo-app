package com.geoapp.bootstrap;

import com.geoapp.config.AppProperties;
import com.geoapp.users.Role;
import com.geoapp.users.UserRepository;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.boot.ApplicationArguments;
import org.springframework.boot.ApplicationRunner;
import org.springframework.core.annotation.Order;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Component;

/** Creates the first admin from APP_ADMIN_EMAIL / APP_ADMIN_PASSWORD when that account does not exist yet. */
@Component
@Order(1)
public class AdminBootstrap implements ApplicationRunner {

    private static final Logger log = LoggerFactory.getLogger(AdminBootstrap.class);

    private final AppProperties props;
    private final UserRepository users;
    private final PasswordEncoder encoder;

    public AdminBootstrap(AppProperties props, UserRepository users, PasswordEncoder encoder) {
        this.props = props;
        this.users = users;
        this.encoder = encoder;
    }

    @Override
    public void run(ApplicationArguments args) {
        String email = props.bootstrapAdmin().email();
        String password = props.bootstrapAdmin().password();
        if (email == null || email.isBlank() || password == null || password.isBlank()) {
            return;
        }
        if (users.findByEmail(email.trim()).isPresent()) {
            return;
        }
        users.insert(email.trim().toLowerCase(), encoder.encode(password), Role.ADMIN);
        log.info("Created bootstrap admin {}", email);
    }
}
