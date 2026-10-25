package com.geoapp;

import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.multipart;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.patch;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.jayway.jsonpath.JsonPath;
import java.nio.charset.StandardCharsets;
import java.util.UUID;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.testcontainers.service.connection.ServiceConnection;
import org.springframework.http.MediaType;
import org.springframework.mock.web.MockMultipartFile;
import org.springframework.test.context.TestPropertySource;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.MvcResult;
import org.springframework.test.web.servlet.request.MockHttpServletRequestBuilder;
import org.testcontainers.containers.PostgreSQLContainer;
import org.testcontainers.junit.jupiter.Container;
import org.testcontainers.junit.jupiter.Testcontainers;
import org.testcontainers.utility.DockerImageName;

@SpringBootTest
@AutoConfigureMockMvc
@Testcontainers
@TestPropertySource(properties = {
        "app.bootstrap-admin.email=admin@test.local",
        "app.bootstrap-admin.password=Admin#12345",
        "app.storage.dir=target/test-media"})
class ApiIntegrationTest {

    @Container
    @ServiceConnection
    static PostgreSQLContainer<?> db = new PostgreSQLContainer<>(
            DockerImageName.parse("postgis/postgis:16-3.4").asCompatibleSubstituteFor("postgres"));

    private static final byte[] JPEG = {
            (byte) 0xFF, (byte) 0xD8, (byte) 0xFF, (byte) 0xE0, 0, 0x10, 'J', 'F', 'I', 'F', 0, 1, 1, 0, 0, 1};

    @Autowired
    MockMvc mvc;

    @Test
    void postIsHiddenUntilApprovedAndOnlyVisibleWithinTwentyMetres() throws Exception {
        double lat = 20.0, lng = 70.0;
        String admin = login("admin@test.local", "Admin#12345");
        String creator = register(email());

        String postId = JsonPath.read(createPost(creator, lat, lng, 8f, JPEG)
                .andExpect(status().isCreated())
                .andExpect(jsonPath("$.status").value("PENDING"))
                .andExpect(jsonPath("$.type").value("IMAGE"))
                .andReturn().getResponse().getContentAsString(), "$.id");

        nearby(lat, lng, null).andExpect(jsonPath("$.length()").value(0));

        mvc.perform(get("/api/admin/posts").param("status", "PENDING").header("Authorization", bearer(admin)))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$[?(@.id=='" + postId + "')]").exists());

        mvc.perform(post("/api/admin/posts/" + postId + "/review")
                        .header("Authorization", bearer(admin))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"decision\":\"APPROVE\"}"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.status").value("APPROVED"));

        // Posted at the point itself: inside the 20 m default radius, public, no login needed.
        nearby(lat, lng, null).andExpect(jsonPath("$.length()").value(1));
        // About 11 m north: still inside.
        nearby(lat + 0.0001, lng, null).andExpect(jsonPath("$.length()").value(1));
        // About 111 m north: outside the default radius...
        nearby(lat + 0.001, lng, null).andExpect(jsonPath("$.length()").value(0));
        // ...and still outside when a bigger radius is asked for, because it is capped at 100 m.
        nearby(lat + 0.0011, lng, 5000.0).andExpect(jsonPath("$.length()").value(0));
    }

    @Test
    void rejectedPostNeverAppearsNearby() throws Exception {
        double lat = 21.0, lng = 71.0;
        String admin = login("admin@test.local", "Admin#12345");
        String creator = register(email());
        String postId = JsonPath.read(createPost(creator, lat, lng, 5f, JPEG)
                .andReturn().getResponse().getContentAsString(), "$.id");

        mvc.perform(post("/api/admin/posts/" + postId + "/review")
                        .header("Authorization", bearer(admin))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"decision\":\"REJECT\",\"reason\":\"Not allowed\"}"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.rejectReason").value("Not allowed"));

        nearby(lat, lng, null).andExpect(jsonPath("$.length()").value(0));
        mvc.perform(get("/api/posts/mine").header("Authorization", bearer(creator)))
                .andExpect(jsonPath("$[0].status").value("REJECTED"));
    }

    @Test
    void adminPostsArePublishedImmediately() throws Exception {
        double lat = 22.0, lng = 72.0;
        String admin = login("admin@test.local", "Admin#12345");
        createPost(admin, lat, lng, 5f, JPEG)
                .andExpect(status().isCreated())
                .andExpect(jsonPath("$.status").value("APPROVED"));
        nearby(lat, lng, null).andExpect(jsonPath("$.length()").value(1));
    }

    @Test
    void uploadsAreCheckedByContentNotByName() throws Exception {
        String creator = register(email());
        byte[] notMedia = "<script>alert(1)</script>".getBytes(StandardCharsets.UTF_8);
        createPost(creator, 23.0, 73.0, 5f, notMedia).andExpect(status().isUnsupportedMediaType());
    }

    @Test
    void lowGpsAccuracyIsRejected() throws Exception {
        String creator = register(email());
        createPost(creator, 24.0, 74.0, 500f, JPEG).andExpect(status().isUnprocessableEntity());
    }

    @Test
    void anonymousCannotPostAndCreatorCannotModerate() throws Exception {
        mvc.perform(multipart("/api/posts")
                        .file(new MockMultipartFile("file", "a.jpg", "image/jpeg", JPEG))
                        .param("lat", "25").param("lng", "75"))
                .andExpect(status().isUnauthorized());

        String creator = register(email());
        mvc.perform(get("/api/admin/posts").header("Authorization", bearer(creator)))
                .andExpect(status().isForbidden());
    }

    @Test
    void blockedUserLosesAccessImmediately() throws Exception {
        String admin = login("admin@test.local", "Admin#12345");
        String email = email();
        MvcResult reg = mvc.perform(post("/api/auth/register").contentType(MediaType.APPLICATION_JSON)
                .content("{\"email\":\"" + email + "\",\"password\":\"Password#123\"}")).andReturn();
        String token = JsonPath.read(reg.getResponse().getContentAsString(), "$.accessToken");
        String userId = JsonPath.read(reg.getResponse().getContentAsString(), "$.user.id");

        mvc.perform(get("/api/auth/me").header("Authorization", bearer(token))).andExpect(status().isOk());

        mvc.perform(patch("/api/admin/users/" + userId)
                        .header("Authorization", bearer(admin))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"status\":\"BLOCKED\"}"))
                .andExpect(status().isOk());

        mvc.perform(get("/api/auth/me").header("Authorization", bearer(token))).andExpect(status().isUnauthorized());
        mvc.perform(post("/api/auth/login").contentType(MediaType.APPLICATION_JSON)
                        .content("{\"email\":\"" + email + "\",\"password\":\"Password#123\"}"))
                .andExpect(status().isForbidden());
    }

    @Test
    void refreshTokenWorksOnceThenIsRotated() throws Exception {
        MvcResult reg = mvc.perform(post("/api/auth/register").contentType(MediaType.APPLICATION_JSON)
                .content("{\"email\":\"" + email() + "\",\"password\":\"Password#123\"}")).andReturn();
        String refresh = JsonPath.read(reg.getResponse().getContentAsString(), "$.refreshToken");
        String body = "{\"refreshToken\":\"" + refresh + "\"}";

        mvc.perform(post("/api/auth/refresh").contentType(MediaType.APPLICATION_JSON).content(body))
                .andExpect(status().isOk());
        mvc.perform(post("/api/auth/refresh").contentType(MediaType.APPLICATION_JSON).content(body))
                .andExpect(status().isUnauthorized());
    }

    @Test
    void duplicateEmailAndWeakPasswordAreRejected() throws Exception {
        String email = email();
        register(email);
        mvc.perform(post("/api/auth/register").contentType(MediaType.APPLICATION_JSON)
                        .content("{\"email\":\"" + email.toUpperCase() + "\",\"password\":\"Password#123\"}"))
                .andExpect(status().isConflict());
        mvc.perform(post("/api/auth/register").contentType(MediaType.APPLICATION_JSON)
                        .content("{\"email\":\"" + email() + "\",\"password\":\"short\"}"))
                .andExpect(status().isBadRequest());
    }

    @Test
    void adminCanPostOnBehalfOfAnotherUser() throws Exception {
        double lat = 26.0, lng = 76.0;
        String admin = login("admin@test.local", "Admin#12345");
        MvcResult reg = registerFull(email());
        String creatorToken = JsonPath.read(reg.getResponse().getContentAsString(), "$.accessToken");
        String creatorId = JsonPath.read(reg.getResponse().getContentAsString(), "$.user.id");

        createPostAs(admin, lat, lng, creatorId)
                .andExpect(status().isCreated())
                .andExpect(jsonPath("$.status").value("APPROVED"))
                .andExpect(jsonPath("$.authorId").value(creatorId));

        nearby(lat, lng, null).andExpect(jsonPath("$.length()").value(1));
        // The post belongs to the creator, who sees it in their own list.
        mvc.perform(get("/api/posts/mine").header("Authorization", bearer(creatorToken)))
                .andExpect(jsonPath("$[0].authorId").value(creatorId))
                .andExpect(jsonPath("$[0].status").value("APPROVED"));
    }

    @Test
    void creatorCannotPostAsSomeoneElse() throws Exception {
        String creator = register(email());
        MvcResult other = registerFull(email());
        String otherId = JsonPath.read(other.getResponse().getContentAsString(), "$.user.id");
        createPostAs(creator, 27.0, 77.0, otherId).andExpect(status().isForbidden());
    }

    @Test
    void cannotPostAsUnknownOrBlockedUser() throws Exception {
        String admin = login("admin@test.local", "Admin#12345");
        createPostAs(admin, 28.0, 78.0, UUID.randomUUID().toString()).andExpect(status().isNotFound());

        MvcResult reg = registerFull(email());
        String id = JsonPath.read(reg.getResponse().getContentAsString(), "$.user.id");
        mvc.perform(patch("/api/admin/users/" + id).header("Authorization", bearer(admin))
                .contentType(MediaType.APPLICATION_JSON).content("{\"status\":\"BLOCKED\"}"))
                .andExpect(status().isOk());
        createPostAs(admin, 28.0, 78.0, id).andExpect(status().isConflict());
    }

    // ---- helpers ----

    private MvcResult registerFull(String email) throws Exception {
        return mvc.perform(post("/api/auth/register").contentType(MediaType.APPLICATION_JSON)
                        .content("{\"email\":\"" + email + "\",\"password\":\"Password#123\"}"))
                .andExpect(status().isCreated()).andReturn();
    }

    private org.springframework.test.web.servlet.ResultActions createPostAs(
            String token, double lat, double lng, String authorId) throws Exception {
        return mvc.perform(multipart("/api/posts")
                .file(new MockMultipartFile("file", "upload.jpg", "image/jpeg", JPEG))
                .param("lat", String.valueOf(lat))
                .param("lng", String.valueOf(lng))
                .param("authorId", authorId)
                .header("Authorization", bearer(token)));
    }

    private static String email() {
        return "user-" + UUID.randomUUID() + "@test.local";
    }

    private static String bearer(String token) {
        return "Bearer " + token;
    }

    private String register(String email) throws Exception {
        MvcResult r = mvc.perform(post("/api/auth/register").contentType(MediaType.APPLICATION_JSON)
                        .content("{\"email\":\"" + email + "\",\"password\":\"Password#123\"}"))
                .andExpect(status().isCreated()).andReturn();
        return JsonPath.read(r.getResponse().getContentAsString(), "$.accessToken");
    }

    private String login(String email, String password) throws Exception {
        MvcResult r = mvc.perform(post("/api/auth/login").contentType(MediaType.APPLICATION_JSON)
                        .content("{\"email\":\"" + email + "\",\"password\":\"" + password + "\"}"))
                .andExpect(status().isOk()).andReturn();
        return JsonPath.read(r.getResponse().getContentAsString(), "$.accessToken");
    }

    private org.springframework.test.web.servlet.ResultActions createPost(
            String token, double lat, double lng, float accuracy, byte[] bytes) throws Exception {
        MockHttpServletRequestBuilder req = multipart("/api/posts")
                .file(new MockMultipartFile("file", "upload.jpg", "image/jpeg", bytes))
                .param("lat", String.valueOf(lat))
                .param("lng", String.valueOf(lng))
                .param("accuracy", String.valueOf(accuracy))
                .param("caption", "test")
                .header("Authorization", bearer(token));
        return mvc.perform(req);
    }

    private org.springframework.test.web.servlet.ResultActions nearby(double lat, double lng, Double radius)
            throws Exception {
        MockHttpServletRequestBuilder req = get("/api/posts/nearby")
                .param("lat", String.valueOf(lat)).param("lng", String.valueOf(lng));
        if (radius != null) {
            req.param("radius", String.valueOf(radius));
        }
        return mvc.perform(req).andExpect(status().isOk());
    }
}
