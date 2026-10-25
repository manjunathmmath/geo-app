package com.geoapp.seed;

import com.geoapp.media.StorageService;
import com.geoapp.posts.PostRepository;
import com.geoapp.posts.PostStatus;
import com.geoapp.posts.PostType;
import com.geoapp.users.Role;
import com.geoapp.users.User;
import com.geoapp.users.UserRepository;
import com.geoapp.users.UserStatus;
import java.awt.Color;
import java.awt.Font;
import java.awt.GradientPaint;
import java.awt.Graphics2D;
import java.awt.RenderingHints;
import java.awt.image.BufferedImage;
import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.UncheckedIOException;
import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.List;
import java.util.UUID;
import javax.imageio.ImageIO;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.ApplicationArguments;
import org.springframework.boot.ApplicationRunner;
import org.springframework.context.annotation.Profile;
import org.springframework.core.annotation.Order;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Component;

/**
 * Development-only demo data (profile "dev"): users in every state, approved / pending / rejected
 * posts around a centre point, and reports. Posts are placed at known distances from the centre so
 * the 20 m radius is easy to check. Set SEED_LAT / SEED_LNG to your own location to see them on a phone.
 * Images are drawn and audio clips are synthesised on the fly, so no sample files are needed.
 * There are no video samples: a playable MP4 cannot be generated without an encoder.
 */
@Component
@Profile("dev")
@Order(2)
public class DevSeedData implements ApplicationRunner {

    private static final Logger log = LoggerFactory.getLogger(DevSeedData.class);

    static final String ADMIN_EMAIL = "admin@geoapp.local";
    static final String ADMIN_PASSWORD = "Admin#12345";
    static final String USER_PASSWORD = "Password#123";

    static {
        System.setProperty("java.awt.headless", "true");
    }

    private final UserRepository users;
    private final PostRepository posts;
    private final StorageService storage;
    private final PasswordEncoder encoder;
    private final double centreLat;
    private final double centreLng;

    public DevSeedData(UserRepository users, PostRepository posts, StorageService storage, PasswordEncoder encoder,
                       @Value("${app.seed.lat:12.9716}") double centreLat,
                       @Value("${app.seed.lng:77.5946}") double centreLng) {
        this.users = users;
        this.posts = posts;
        this.storage = storage;
        this.encoder = encoder;
        this.centreLat = centreLat;
        this.centreLng = centreLng;
    }

    @Override
    public void run(ApplicationArguments args) {
        if (users.findByEmail("alice@geoapp.local").isPresent()) {
            log.info("Dev seed data already present, skipping");
            return;
        }
        User admin = users.findByEmail(ADMIN_EMAIL)
                .orElseGet(() -> users.insert(ADMIN_EMAIL, encoder.encode(ADMIN_PASSWORD), Role.ADMIN));
        User alice = creator("alice@geoapp.local");
        User bob = creator("bob@geoapp.local");
        User carol = creator("carol@geoapp.local");
        User mallory = creator("mallory@geoapp.local");

        List<UUID> approvedNear = new ArrayList<>();
        int n = 0;

        // Approved and inside the default 20 m radius.
        approvedNear.add(approved(admin, alice, 3, 0, false, "Street art on the corner wall", n++));
        approvedNear.add(approved(admin, bob, 8, 90, false, "The old banyan tree", n++));
        approvedNear.add(approved(admin, carol, 12, 180, true, "Temple bells (sample tone)", n++));
        approvedNear.add(approved(admin, alice, 15, 270, false, "Tea stall menu board", n++));
        approvedNear.add(approved(admin, bob, 18, 45, true, "Street sounds (sample tone)", n++));
        // Posted by the admin: published immediately.
        add(admin, 10, 135, false, "Welcome to the neighbourhood (admin post)", PostStatus.APPROVED, n++);

        // Approved but outside 20 m: visible only with a larger radius or from somewhere else.
        approved(admin, carol, 35, 20, false, "Bus stop, 35 m away", n++);
        approved(admin, alice, 60, 110, false, "Playground, 60 m away", n++);
        approved(admin, bob, 90, 200, true, "Fountain sound, 90 m away", n++);
        approved(admin, carol, 250, 300, false, "Market entrance, 250 m away", n++);
        approved(admin, alice, 800, 60, false, "Lake view, 800 m away", n++);

        // Waiting for moderation: enough to exercise paging in the admin queue.
        String[] pendingCaptions = {"New cafe opening", "Cat on the wall", "Sunset from the roof", "Local band rehearsal",
                "Pothole near the gate", "Fresh flowers stall", "Evening prayer sounds", "Bicycle repair shop",
                "Wall mural in progress", "Morning mist", "Auto stand", "Book swap corner"};
        User[] authors = {alice, bob, carol};
        for (int i = 0; i < pendingCaptions.length; i++) {
            add(authors[i % 3], 4 + i * 2, i * 30, i % 4 == 3, pendingCaptions[i], PostStatus.PENDING, n++);
        }

        // Rejected, each with a reason a creator would see.
        rejected(admin, mallory, 6, 10, "Buy cheap watches here!", "Advertising is not allowed", n++);
        rejected(admin, bob, 9, 220, "Blurry photo", "Image is too blurry to see", n++);
        rejected(admin, carol, 14, 300, "Someone's face", "Shows an identifiable person without consent", n++);

        // Reports on published posts, so the moderator has something to look at.
        posts.report(approvedNear.get(0), bob.id(), "Looks like an advertisement");
        posts.report(approvedNear.get(0), carol.id(), "Spam");
        posts.report(approvedNear.get(3), alice.id(), "Wrong place, this is not at this location");

        users.update(mallory.id(), UserStatus.BLOCKED, null);

        log.info("""

                ---- Dev seed data created (centre {}, {}) ----
                Admin   : {} / {}
                Creators: alice@, bob@, carol@geoapp.local / {}
                Blocked : mallory@geoapp.local
                Posts   : 6 approved within 20 m, 5 approved farther away, 12 pending, 3 rejected, 3 reports
                -----------------------------------------------""",
                centreLat, centreLng, ADMIN_EMAIL, ADMIN_PASSWORD, USER_PASSWORD);
    }

    private User creator(String email) {
        return users.insert(email, encoder.encode(USER_PASSWORD), Role.CREATOR);
    }

    private UUID approved(User admin, User author, double metres, double bearing, boolean audio, String caption, int i) {
        UUID id = add(author, metres, bearing, audio, caption, PostStatus.PENDING, i);
        posts.review(id, admin.id(), PostStatus.APPROVED, null);
        return id;
    }

    private void rejected(User admin, User author, double metres, double bearing, String caption, String reason, int i) {
        UUID id = add(author, metres, bearing, false, caption, PostStatus.PENDING, i);
        posts.review(id, admin.id(), PostStatus.REJECTED, reason);
    }

    private UUID add(User author, double metres, double bearing, boolean audio, String caption,
                     PostStatus status, int i) {
        StorageService.Stored stored = storage.saveBytes(audio ? tone(220 + 40 * (i % 8)) : image(caption, i));
        double[] p = offset(centreLat, centreLng, metres, bearing);
        PostType type = stored.type();
        return posts.insert(author.id(), type, stored.path(), caption, p[0], p[1], 5f + (i % 6), status);
    }

    /** Moves a point by the given distance along a compass bearing (small-distance approximation). */
    static double[] offset(double lat, double lng, double metres, double bearingDeg) {
        double rad = Math.toRadians(bearingDeg);
        double dLat = metres * Math.cos(rad) / 111_320.0;
        double dLng = metres * Math.sin(rad) / (111_320.0 * Math.cos(Math.toRadians(lat)));
        return new double[] {lat + dLat, lng + dLng};
    }

    private static byte[] image(String label, int i) {
        int w = 640;
        int h = 480;
        BufferedImage img = new BufferedImage(w, h, BufferedImage.TYPE_INT_RGB);
        Graphics2D g = img.createGraphics();
        try {
            float hue = (i * 0.13f) % 1f;
            g.setPaint(new GradientPaint(0, 0, Color.getHSBColor(hue, 0.55f, 0.85f),
                    w, h, Color.getHSBColor((hue + 0.12f) % 1f, 0.65f, 0.50f)));
            g.fillRect(0, 0, w, h);
            g.setRenderingHint(RenderingHints.KEY_TEXT_ANTIALIASING, RenderingHints.VALUE_TEXT_ANTIALIAS_ON);
            g.setColor(Color.WHITE);
            g.setFont(new Font(Font.SANS_SERIF, Font.BOLD, 34));
            int y = 200;
            for (String line : wrap(label, 24)) {
                g.drawString(line, 36, y);
                y += 46;
            }
        } finally {
            g.dispose();
        }
        try (ByteArrayOutputStream out = new ByteArrayOutputStream()) {
            ImageIO.write(img, "png", out);
            return out.toByteArray();
        } catch (IOException e) {
            throw new UncheckedIOException(e);
        }
    }

    private static List<String> wrap(String text, int max) {
        List<String> lines = new ArrayList<>();
        StringBuilder cur = new StringBuilder();
        for (String word : text.split(" ")) {
            if (cur.length() > 0 && cur.length() + word.length() + 1 > max) {
                lines.add(cur.toString());
                cur.setLength(0);
            }
            if (cur.length() > 0) cur.append(' ');
            cur.append(word);
        }
        if (cur.length() > 0) lines.add(cur.toString());
        return lines;
    }

    /** A 3-second sine tone as a 16-bit mono WAV, with short fades so it does not click. */
    private static byte[] tone(double freq) {
        int rate = 22_050;
        int samples = rate * 3;
        ByteBuffer b = ByteBuffer.allocate(44 + samples * 2).order(ByteOrder.LITTLE_ENDIAN);
        b.put("RIFF".getBytes(StandardCharsets.US_ASCII)).putInt(36 + samples * 2)
                .put("WAVE".getBytes(StandardCharsets.US_ASCII))
                .put("fmt ".getBytes(StandardCharsets.US_ASCII)).putInt(16)
                .putShort((short) 1).putShort((short) 1).putInt(rate).putInt(rate * 2)
                .putShort((short) 2).putShort((short) 16)
                .put("data".getBytes(StandardCharsets.US_ASCII)).putInt(samples * 2);
        int fade = rate / 10;
        for (int i = 0; i < samples; i++) {
            double env = Math.min(1.0, Math.min(i, samples - 1 - i) / (double) fade);
            b.putShort((short) (Math.sin(2 * Math.PI * freq * i / rate) * 9000 * env));
        }
        return b.array();
    }
}
