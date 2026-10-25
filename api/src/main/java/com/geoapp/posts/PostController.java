package com.geoapp.posts;

import com.geoapp.security.AuthUser;
import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;
import java.util.List;
import java.util.UUID;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RequestPart;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.multipart.MultipartFile;

@RestController
@RequestMapping("/api/posts")
public class PostController {

    public record ReportRequest(@NotBlank @Size(max = 500) String reason) {}

    private final PostService service;

    public PostController(PostService service) {
        this.service = service;
    }

    /** Public: anyone can see approved posts around a point. */
    @GetMapping("/nearby")
    List<PostView> nearby(@RequestParam double lat, @RequestParam double lng,
                          @RequestParam(required = false) Double radius) {
        return service.nearby(lat, lng, radius);
    }

    @PostMapping(consumes = MediaType.MULTIPART_FORM_DATA_VALUE)
    ResponseEntity<PostView> create(@AuthenticationPrincipal AuthUser user,
                                    @RequestPart("file") MultipartFile file,
                                    @RequestParam double lat,
                                    @RequestParam double lng,
                                    @RequestParam(required = false) Float accuracy,
                                    @RequestParam(required = false) String caption,
                                    @RequestParam(required = false) UUID authorId) {
        return ResponseEntity.status(HttpStatus.CREATED)
                .body(service.create(user, file, lat, lng, accuracy, caption, authorId));
    }

    @GetMapping("/mine")
    List<PostView> mine(@AuthenticationPrincipal AuthUser user,
                        @RequestParam(defaultValue = "50") int limit,
                        @RequestParam(defaultValue = "0") int offset) {
        return service.mine(user.id(), limit, offset);
    }

    @PostMapping("/{id}/report")
    ResponseEntity<Void> report(@AuthenticationPrincipal AuthUser user, @PathVariable UUID id,
                                @Valid @RequestBody ReportRequest req) {
        service.report(id, user.id(), req.reason());
        return ResponseEntity.noContent().build();
    }
}
