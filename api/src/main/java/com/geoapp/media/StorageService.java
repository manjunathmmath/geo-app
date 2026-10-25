package com.geoapp.media;

import com.geoapp.common.ApiException;
import com.geoapp.config.AppProperties;
import com.geoapp.posts.PostType;
import java.io.IOException;
import java.io.InputStream;
import java.io.UncheckedIOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.time.LocalDate;
import java.util.UUID;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.web.multipart.MultipartFile;

/**
 * Stores uploads on local disk under random names. The file type is decided from the
 * file's own first bytes, never from the client-supplied name or Content-Type.
 */
@Service
public class StorageService {

    public record Stored(String path, PostType type) {}

    private record Kind(String ext, PostType type) {}

    private final Path root;

    public StorageService(AppProperties props) {
        this.root = Path.of(props.storage().dir()).toAbsolutePath().normalize();
        try {
            Files.createDirectories(root);
        } catch (IOException e) {
            throw new UncheckedIOException(e);
        }
    }

    public Path root() {
        return root;
    }

    public Stored save(MultipartFile file) {
        if (file.isEmpty()) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "File is empty");
        }
        try {
            byte[] head;
            try (InputStream in = file.getInputStream()) {
                head = in.readNBytes(16);
            }
            Kind kind = requireKind(head);
            String rel = relativePath(kind);
            Path dest = resolve(rel);
            file.transferTo(dest);
            return new Stored(rel, kind.type());
        } catch (IOException e) {
            throw new UncheckedIOException(e);
        }
    }

    public Stored saveBytes(byte[] data) {
        Kind kind = requireKind(data);
        String rel = relativePath(kind);
        try {
            Files.write(resolve(rel), data);
        } catch (IOException e) {
            throw new UncheckedIOException(e);
        }
        return new Stored(rel, kind.type());
    }

    private Path resolve(String rel) throws IOException {
        Path dest = root.resolve(rel).normalize();
        if (!dest.startsWith(root)) {
            throw new IllegalStateException("Path escapes storage root");
        }
        Files.createDirectories(dest.getParent());
        return dest;
    }

    private static String relativePath(Kind kind) {
        LocalDate d = LocalDate.now();
        return "%d/%02d/%s.%s".formatted(d.getYear(), d.getMonthValue(), UUID.randomUUID(), kind.ext());
    }

    private static Kind requireKind(byte[] h) {
        Kind kind = sniff(h);
        if (kind == null) {
            throw new ApiException(HttpStatus.UNSUPPORTED_MEDIA_TYPE,
                    "Unsupported file type. Allowed: JPEG, PNG, WebP, MP4, M4A, MP3, AAC, WAV, OGG");
        }
        return kind;
    }

    private static Kind sniff(byte[] h) {
        if (h.length < 12) {
            return null;
        }
        if (u(h[0]) == 0xFF && u(h[1]) == 0xD8 && u(h[2]) == 0xFF) return new Kind("jpg", PostType.IMAGE);
        if (u(h[0]) == 0x89 && at(h, 1, "PNG")) return new Kind("png", PostType.IMAGE);
        if (at(h, 0, "RIFF")) {
            if (at(h, 8, "WEBP")) return new Kind("webp", PostType.IMAGE);
            if (at(h, 8, "WAVE")) return new Kind("wav", PostType.AUDIO);
            return null;
        }
        if (at(h, 4, "ftyp")) {
            String brand = new String(h, 8, 4, StandardCharsets.ISO_8859_1);
            if (brand.startsWith("hei") || brand.startsWith("hev") || brand.equals("mif1") || brand.equals("avif")) {
                return null; // HEIC/AVIF stills are not video
            }
            return brand.equals("M4A ") ? new Kind("m4a", PostType.AUDIO) : new Kind("mp4", PostType.VIDEO);
        }
        if (at(h, 0, "OggS")) return new Kind("ogg", PostType.AUDIO);
        if (at(h, 0, "ID3")) return new Kind("mp3", PostType.AUDIO);
        if (u(h[0]) == 0xFF && (u(h[1]) & 0xF6) == 0xF0) return new Kind("aac", PostType.AUDIO);
        if (u(h[0]) == 0xFF && (u(h[1]) & 0xE0) == 0xE0) return new Kind("mp3", PostType.AUDIO);
        return null;
    }

    private static int u(byte b) {
        return b & 0xFF;
    }

    private static boolean at(byte[] h, int offset, String s) {
        byte[] expected = s.getBytes(StandardCharsets.ISO_8859_1);
        if (h.length < offset + expected.length) {
            return false;
        }
        for (int i = 0; i < expected.length; i++) {
            if (h[offset + i] != expected[i]) {
                return false;
            }
        }
        return true;
    }
}
