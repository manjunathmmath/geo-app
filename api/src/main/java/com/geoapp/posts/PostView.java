package com.geoapp.posts;

import java.time.Instant;
import java.util.UUID;

/** A post as returned by the API. distanceM is only set by the nearby query. */
public record PostView(
        UUID id,
        UUID authorId,
        String type,
        String mediaUrl,
        String caption,
        double lat,
        double lng,
        Float accuracyM,
        String status,
        Instant createdAt,
        String rejectReason,
        Double distanceM) {}
