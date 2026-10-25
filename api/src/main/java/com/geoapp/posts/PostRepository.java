package com.geoapp.posts;

import java.time.OffsetDateTime;
import java.util.List;
import java.util.Optional;
import java.util.UUID;
import org.springframework.jdbc.core.RowMapper;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Repository;

@Repository
public class PostRepository {

    private static final String COLS = """
            p.id, p.author_id, p.type, p.media_path, p.caption,
            ST_Y(CAST(p.location AS geometry)) AS lat, ST_X(CAST(p.location AS geometry)) AS lng,
            p.accuracy_m, p.status, p.created_at, p.reject_reason""";

    private static final String NO_DISTANCE = "CAST(NULL AS double precision) AS distance_m";

    private static final RowMapper<PostView> MAPPER = (rs, i) -> new PostView(
            rs.getObject("id", UUID.class),
            rs.getObject("author_id", UUID.class),
            rs.getString("type"),
            "/media/" + rs.getString("media_path"),
            rs.getString("caption"),
            rs.getDouble("lat"),
            rs.getDouble("lng"),
            rs.getObject("accuracy_m", Float.class),
            rs.getString("status"),
            rs.getObject("created_at", OffsetDateTime.class).toInstant(),
            rs.getString("reject_reason"),
            rs.getObject("distance_m", Double.class));

    private final JdbcClient jdbc;

    public PostRepository(JdbcClient jdbc) {
        this.jdbc = jdbc;
    }

    public UUID insert(UUID authorId, PostType type, String mediaPath, String caption,
                       double lat, double lng, Float accuracyM, PostStatus status) {
        return insert(authorId, type, mediaPath, caption, lat, lng, accuracyM, status, null);
    }

    /** reviewerId is recorded as the approver when a post is created already approved (admin posts). */
    public UUID insert(UUID authorId, PostType type, String mediaPath, String caption,
                       double lat, double lng, Float accuracyM, PostStatus status, UUID reviewerId) {
        return jdbc.sql("""
                        INSERT INTO posts (author_id, type, media_path, caption, location, accuracy_m, status,
                                           reviewed_by, reviewed_at)
                        VALUES (:author, :type, :path, :caption,
                                CAST(ST_SetSRID(ST_MakePoint(:lng, :lat), 4326) AS geography), :accuracy, :status,
                                CAST(:reviewer AS uuid),
                                CASE WHEN CAST(:reviewer AS uuid) IS NULL THEN NULL ELSE now() END)
                        RETURNING id""")
                .param("reviewer", reviewerId)
                .param("author", authorId)
                .param("type", type.name())
                .param("path", mediaPath)
                .param("caption", caption)
                .param("lng", lng)
                .param("lat", lat)
                .param("accuracy", accuracyM)
                .param("status", status.name())
                .query(UUID.class).single();
    }

    public Optional<PostView> findById(UUID id) {
        return jdbc.sql("SELECT " + COLS + ", " + NO_DISTANCE + " FROM posts p WHERE p.id = :id")
                .param("id", id).query(MAPPER).optional();
    }

    /** Approved posts within radiusM metres of the point, closest first. */
    public List<PostView> nearby(double lat, double lng, double radiusM, int limit) {
        return jdbc.sql("""
                        WITH q AS (SELECT CAST(ST_SetSRID(ST_MakePoint(:lng, :lat), 4326) AS geography) AS pt)
                        SELECT %s, ST_Distance(p.location, q.pt) AS distance_m
                        FROM posts p, q
                        WHERE p.status = 'APPROVED' AND ST_DWithin(p.location, q.pt, :radius)
                        ORDER BY distance_m ASC, p.created_at DESC
                        LIMIT :limit""".formatted(COLS))
                .param("lng", lng).param("lat", lat).param("radius", radiusM).param("limit", limit)
                .query(MAPPER).list();
    }

    public List<PostView> byAuthor(UUID authorId, int limit, int offset) {
        return jdbc.sql("SELECT " + COLS + ", " + NO_DISTANCE + """
                         FROM posts p WHERE p.author_id = :author
                        ORDER BY p.created_at DESC LIMIT :limit OFFSET :offset""")
                .param("author", authorId).param("limit", limit).param("offset", offset)
                .query(MAPPER).list();
    }

    /** Oldest first, so the moderation queue is worked in arrival order. */
    public List<PostView> byStatus(PostStatus status, int limit, int offset) {
        return jdbc.sql("SELECT " + COLS + ", " + NO_DISTANCE + """
                         FROM posts p WHERE p.status = :status
                        ORDER BY p.created_at ASC LIMIT :limit OFFSET :offset""")
                .param("status", status.name()).param("limit", limit).param("offset", offset)
                .query(MAPPER).list();
    }

    /** Returns 0 when the post does not exist or already has that status. */
    public int review(UUID id, UUID adminId, PostStatus status, String reason) {
        return jdbc.sql("""
                        UPDATE posts
                        SET status = :status, reviewed_by = :admin, reviewed_at = now(), reject_reason = :reason
                        WHERE id = :id AND status <> :status""")
                .param("id", id).param("admin", adminId)
                .param("status", status.name()).param("reason", reason)
                .update();
    }

    /** One report per user per post; repeating it is a no-op. Throws DataIntegrityViolationException if the post is missing. */
    public void report(UUID postId, UUID reporterId, String reason) {
        jdbc.sql("""
                        INSERT INTO reports (post_id, reporter_id, reason) VALUES (:post, :reporter, :reason)
                        ON CONFLICT (post_id, reporter_id) DO NOTHING""")
                .param("post", postId).param("reporter", reporterId).param("reason", reason)
                .update();
    }
}
