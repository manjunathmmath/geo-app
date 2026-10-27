package com.geoapp.media;

import com.geoapp.config.AppProperties;
import com.geoapp.posts.PostType;
import java.io.IOException;
import java.io.OutputStream;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.List;
import java.util.Optional;
import java.util.concurrent.TimeUnit;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;

/**
 * Makes a small JPEG preview (480 px wide) of a photo or a video's first moments with ffmpeg.
 * Best effort: when ffmpeg is missing or fails, the post is still created, just without a preview.
 */
@Service
public class ThumbnailService {

    private static final Logger log = LoggerFactory.getLogger(ThumbnailService.class);
    private static final String SCALE = "scale='min(480,iw)':-2";
    private static final long TIMEOUT_SECONDS = 20;

    private final String ffmpeg;
    private final StorageService storage;

    public ThumbnailService(AppProperties props, StorageService storage) {
        this.ffmpeg = props.ffmpeg() == null || props.ffmpeg().path() == null || props.ffmpeg().path().isBlank()
                ? "ffmpeg"
                : props.ffmpeg().path();
        this.storage = storage;
    }

    /** Returns the preview's path relative to the storage root, or empty when none could be made. */
    public Optional<String> create(String mediaPath, PostType type) {
        if (mediaPath == null || (type != PostType.IMAGE && type != PostType.VIDEO)) {
            return Optional.empty();
        }
        Path root = storage.root();
        Path in = root.resolve(mediaPath).normalize();
        String thumbRel = mediaPath.replaceFirst("\\.[^./]+$", "") + ".thumb.jpg";
        Path out = root.resolve(thumbRel).normalize();
        if (!in.startsWith(root) || !out.startsWith(root) || !Files.isRegularFile(in)) {
            return Optional.empty();
        }
        // A video is sampled half a second in; if it is shorter than that, take the very first frame.
        if (type == PostType.VIDEO && run(in, out, "0.5")) return Optional.of(thumbRel);
        if (run(in, out, null)) return Optional.of(thumbRel);
        return Optional.empty();
    }

    private boolean run(Path in, Path out, String seek) {
        List<String> cmd = new ArrayList<>(List.of(ffmpeg, "-y", "-loglevel", "error"));
        if (seek != null) cmd.addAll(List.of("-ss", seek));
        cmd.addAll(List.of("-i", in.toString(), "-frames:v", "1", "-vf", SCALE, "-q:v", "4", out.toString()));
        try {
            Process p = new ProcessBuilder(cmd).redirectErrorStream(true).start();
            if (!p.waitFor(TIMEOUT_SECONDS, TimeUnit.SECONDS)) {
                p.destroyForcibly();
                log.warn("ffmpeg timed out making a preview of {}", in.getFileName());
                return false;
            }
            p.getInputStream().transferTo(OutputStream.nullOutputStream());
            boolean ok = p.exitValue() == 0 && Files.isRegularFile(out) && Files.size(out) > 0;
            if (!ok) Files.deleteIfExists(out);
            return ok;
        } catch (IOException e) {
            log.debug("ffmpeg is not available ({}); posts will have no preview image", e.getMessage());
            return false;
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            return false;
        }
    }
}
