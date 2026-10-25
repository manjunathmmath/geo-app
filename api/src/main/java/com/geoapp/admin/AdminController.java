package com.geoapp.admin;

import com.geoapp.common.ApiException;
import com.geoapp.posts.PostRepository;
import com.geoapp.posts.PostService;
import com.geoapp.posts.PostStatus;
import com.geoapp.posts.PostView;
import com.geoapp.security.AuthUser;
import com.geoapp.users.Role;
import com.geoapp.users.UserDto;
import com.geoapp.users.UserRepository;
import com.geoapp.users.UserStatus;
import jakarta.validation.Valid;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;
import java.util.List;
import java.util.UUID;
import org.springframework.http.HttpStatus;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PatchMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/** Moderation and user management. The whole /api/admin tree requires the ADMIN role (see SecurityConfig). */
@RestController
@RequestMapping("/api/admin")
public class AdminController {

    public enum Decision { APPROVE, REJECT }

    public record ReviewRequest(@NotNull Decision decision, @Size(max = 500) String reason) {}

    public record UpdateUserRequest(UserStatus status, Role role) {}

    private final PostRepository posts;
    private final UserRepository users;

    public AdminController(PostRepository posts, UserRepository users) {
        this.posts = posts;
        this.users = users;
    }

    @GetMapping("/posts")
    List<PostView> posts(@RequestParam(defaultValue = "PENDING") PostStatus status,
                         @RequestParam(defaultValue = "50") int limit,
                         @RequestParam(defaultValue = "0") int offset) {
        return posts.byStatus(status, PostService.clamp(limit), Math.max(offset, 0));
    }

    @PostMapping("/posts/{id}/review")
    PostView review(@AuthenticationPrincipal AuthUser admin, @PathVariable UUID id,
                    @Valid @RequestBody ReviewRequest req) {
        PostStatus status = req.decision() == Decision.APPROVE ? PostStatus.APPROVED : PostStatus.REJECTED;
        String reason = status == PostStatus.REJECTED ? req.reason() : null;
        if (posts.review(id, admin.id(), status, reason) == 0) {
            if (posts.findById(id).isEmpty()) {
                throw new ApiException(HttpStatus.NOT_FOUND, "Post not found");
            }
            throw new ApiException(HttpStatus.CONFLICT, "Post is already " + status);
        }
        return posts.findById(id).orElseThrow();
    }

    @GetMapping("/users")
    List<UserDto> users(@RequestParam(defaultValue = "50") int limit,
                        @RequestParam(defaultValue = "0") int offset) {
        return users.list(PostService.clamp(limit), Math.max(offset, 0)).stream().map(UserDto::from).toList();
    }

    @PatchMapping("/users/{id}")
    UserDto updateUser(@AuthenticationPrincipal AuthUser admin, @PathVariable UUID id,
                       @RequestBody UpdateUserRequest req) {
        if (req.status() == null && req.role() == null) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "Nothing to update");
        }
        if (id.equals(admin.id()) && (req.status() == UserStatus.BLOCKED || req.role() == Role.CREATOR)) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "You cannot block or demote your own account");
        }
        if (users.update(id, req.status(), req.role()) == 0) {
            throw new ApiException(HttpStatus.NOT_FOUND, "User not found");
        }
        return UserDto.from(users.findById(id).orElseThrow());
    }
}
