package com.geoapp.posts;

import java.time.Instant;
import java.util.UUID;

/**
 * A post as returned by the API. mediaUrl is null for TEXT posts, and text is null for the others
 * (they use caption). thumbUrl is a small preview image of a photo or video, null when there is none
 * (audio, text, or ffmpeg was not available). distanceM is only set by the nearby query.
 */
public record PostView(
        UUID id,
        UUID authorId,
        String type,
        String mediaUrl,
        String thumbUrl,
        String caption,
        String text,
        double lat,
        double lng,
        Float accuracyM,
        String status,
        Instant createdAt,
        String rejectReason,
        Double distanceM) {}
