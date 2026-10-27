package com.geoapp.posts;

import com.geoapp.common.ApiException;
import com.geoapp.config.AppProperties;
import com.geoapp.media.StorageService;
import com.geoapp.media.ThumbnailService;
import com.geoapp.security.AuthUser;
import com.geoapp.users.Role;
import com.geoapp.users.User;
import com.geoapp.users.UserRepository;
import com.geoapp.users.UserStatus;
import java.util.List;
import java.util.UUID;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.web.multipart.MultipartFile;

@Service
public class PostService {

    private static final int NEARBY_LIMIT = 100;
    private static final int MAX_CAPTION = 500;
    private static final int MAX_TEXT = 1000;

    private final PostRepository posts;
    private final UserRepository users;
    private final StorageService storage;
    private final ThumbnailService thumbnails;
    private final AppProperties.Geo geo;

    public PostService(PostRepository posts, UserRepository users, StorageService storage,
                       ThumbnailService thumbnails, AppProperties props) {
        this.posts = posts;
        this.users = users;
        this.storage = storage;
        this.thumbnails = thumbnails;
        this.geo = props.geo();
    }

    /**
     * Admin posts are published straight away; everyone else's wait for moderation.
     * An admin may pass authorId to post as another active user; the post is then owned by that
     * user, and the admin is recorded as the approver (reviewed_by).
     */
    public PostView create(AuthUser user, MultipartFile file, double lat, double lng,
                           Float accuracyM, String caption, String text, UUID authorId) {
        requireCoordinates(lat, lng);
        UUID author = user.id();
        if (authorId != null && !authorId.equals(user.id())) {
            if (user.role() != Role.ADMIN) {
                throw new ApiException(HttpStatus.FORBIDDEN, "Only an administrator can post as another user");
            }
            User target = users.findById(authorId)
                    .orElseThrow(() -> new ApiException(HttpStatus.NOT_FOUND, "Author not found"));
            if (target.status() == UserStatus.BLOCKED) {
                throw new ApiException(HttpStatus.CONFLICT, "That user is blocked");
            }
            author = target.id();
        }
        if (accuracyM != null && accuracyM > geo.maxAccuracyM()) {
            throw new ApiException(HttpStatus.UNPROCESSABLE_ENTITY,
                    "GPS accuracy is too low (" + Math.round(accuracyM) + " m). Move to an open area and try again.");
        }
        // A post is either a file (photo, audio or video, with an optional caption) or words only.
        // Everything is validated before the file is written to disk.
        boolean hasFile = file != null && !file.isEmpty();
        PostType type;
        String mediaPath = null;
        String thumbPath = null;
        String cleanCaption = null;
        String body = null;
        if (hasFile) {
            cleanCaption = caption == null || caption.isBlank() ? null : caption.trim();
            if (cleanCaption != null && cleanCaption.length() > MAX_CAPTION) {
                throw new ApiException(HttpStatus.BAD_REQUEST,
                        "Caption must be " + MAX_CAPTION + " characters or fewer");
            }
            StorageService.Stored stored = storage.save(file);
            type = stored.type();
            mediaPath = stored.path();
            thumbPath = thumbnails.create(mediaPath, type).orElse(null);
        } else {
            body = text == null || text.isBlank() ? null : text.trim();
            if (body == null) {
                throw new ApiException(HttpStatus.BAD_REQUEST,
                        "Write some text, or attach a photo, audio or video");
            }
            if (body.length() > MAX_TEXT) {
                throw new ApiException(HttpStatus.BAD_REQUEST,
                        "Text must be " + MAX_TEXT + " characters or fewer");
            }
            type = PostType.TEXT;
        }
        boolean admin = user.role() == Role.ADMIN;
        UUID id = posts.insert(author, type, mediaPath, thumbPath, cleanCaption, body, lat, lng, accuracyM,
                admin ? PostStatus.APPROVED : PostStatus.PENDING, admin ? user.id() : null);
        return posts.findById(id).orElseThrow();
    }

    public List<PostView> nearby(double lat, double lng, Double radiusM) {
        requireCoordinates(lat, lng);
        double radius = radiusM == null ? geo.defaultRadiusM() : radiusM;
        if (!(radius > 0)) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "radius must be greater than 0");
        }
        return posts.nearby(lat, lng, Math.min(radius, geo.maxRadiusM()), NEARBY_LIMIT);
    }

    public List<PostView> mine(UUID authorId, int limit, int offset) {
        return posts.byAuthor(authorId, clamp(limit), Math.max(offset, 0));
    }

    public void report(UUID postId, UUID reporterId, String reason) {
        try {
            posts.report(postId, reporterId, reason.trim());
        } catch (DataIntegrityViolationException e) {
            throw new ApiException(HttpStatus.NOT_FOUND, "Post not found");
        }
    }

    public static int clamp(int limit) {
        return Math.max(1, Math.min(limit, 100));
    }

    private static void requireCoordinates(double lat, double lng) {
        if (!Double.isFinite(lat) || !Double.isFinite(lng) || lat < -90 || lat > 90 || lng < -180 || lng > 180) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "Invalid coordinates");
        }
    }
}
