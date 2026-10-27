# geo-app

Location-based media app: people see approved images, audio and video posted within about 20 m of where they stand.

```
api/         Spring Boot 3 (Java 21) REST API, PostgreSQL + PostGIS, Flyway migrations
infra/       docker-compose for the local database
admin-web/   (planned) React moderation panel
mobile/      Flutter app (Android now, iOS later): nearby feed, sign in, post a photo, my posts
```

## Run the API locally

Needs JDK 21 and Docker. Make sure `JAVA_HOME` points at JDK 21 (Maven uses it, not the `java` on PATH).

```powershell
# 1. database (PostgreSQL + PostGIS)
cd infra
docker compose up -d

# 2. API with demo data (profile "dev")
cd ../api
$env:JAVA_HOME = "C:\Program Files\Eclipse Adoptium\jdk-21.0.11.10-hotspot"
mvn spring-boot:run "-Dspring-boot.run.profiles=dev"
```

The API listens on http://localhost:8080. Health check: `GET /actuator/health`.

### Demo data (dev profile only)

| Account | Password | Role |
|---|---|---|
| admin@geoapp.local | Admin#12345 | ADMIN |
| alice@, bob@, carol@geoapp.local | Password#123 | CREATOR |
| mallory@geoapp.local | Password#123 | CREATOR, blocked |

Posts are created around a centre point (default 12.9716, 77.5946). To see them from where you actually are, set your own coordinates before starting:

```powershell
$env:SEED_LAT = "12.9716"; $env:SEED_LNG = "77.5946"
```

- 6 approved posts within 20 m (distances 3, 8, 10, 12, 15, 18 m), 5 approved farther away (35 m to 800 m)
- 12 pending posts (the moderation queue), 3 rejected posts with reasons, 3 reports
- Images are drawn and audio clips are synthesised at start-up. There are no video samples.
- Seeding runs once. To start over: `docker compose down -v` in `infra/`, and delete `api/data/uploads`.

### Try it

```powershell
# public: posts within 20 m of the centre
curl "http://localhost:8080/api/posts/nearby?lat=12.9716&lng=77.5946"

# log in as admin, then list the moderation queue
$t = (curl -s -X POST http://localhost:8080/api/auth/login -H "Content-Type: application/json" `
  -d '{\"email\":\"admin@geoapp.local\",\"password\":\"Admin#12345\"}' | ConvertFrom-Json).accessToken
curl -H "Authorization: Bearer $t" "http://localhost:8080/api/admin/posts?status=PENDING"
```

## Run the admin panel

Needs Node 20.19+ and the API running on port 8080.

```powershell
cd C:\Projects\geo-app\admin-web
npm install --legacy-peer-deps   # npm 10 crashes on Vite's optional peer dependencies without this flag
npm run dev                      # http://localhost:5173
```

Sign in as `admin@geoapp.local` / `Admin#12345` (dev demo data). Creator accounts are refused. The dev server proxies `/api` and `/media` to the API, so there is no CORS setup. `npm run build` type-checks and writes the static site to `dist/`, which Caddy serves in production.

- **Moderation:** Pending / Approved / Rejected tabs, **newest first**, with image / audio / video preview or the post's text, author, GPS accuracy, map link. Approve, reject with a reason, take down an approved post, or restore a rejected one.
- **New post:** a **Photo, audio or video** tab (pick a file, checked against 50 MB, with an optional caption) or a **Text only** tab (up to 1000 characters). Set the location with "Use my current location" (browser GPS, needs HTTPS or localhost) or type latitude / longitude. Admin posts publish immediately. "Post as" lets an admin post on behalf of any active user: the post belongs to that user (it appears in their own list) and the admin is recorded as the approver (`posts.reviewed_by`). Only admins can set an author (API: optional `authorId` on `POST /api/posts`).
- **Users:** block / unblock and promote / demote (you cannot block or demote yourself).

## Run the mobile app

Needs Flutter (`C:\dev\flutter\bin` on PATH), Android Studio's SDK, the API running, and a phone with USB debugging on (or an emulator). Check with `flutter doctor` and `flutter devices`.

```powershell
$env:Path += ";C:\dev\flutter\bin;$env:LOCALAPPDATA\Android\Sdk\platform-tools"
adb devices                          # your phone should be listed as "device"
adb reverse tcp:8080 tcp:8080        # the phone's localhost:8080 now reaches the API on this PC
cd C:\Projects\geo-app\mobile
flutter run
```

- The app defaults to `http://localhost:8080`, which is why `adb reverse` is used. For another address: `flutter run --dart-define=API_BASE=http://192.168.1.20:8080` (phone and PC on the same Wi-Fi, and allow port 8080 in Windows Firewall). On an Android emulator the PC is `http://10.0.2.2:8080`.
- Plain `http://` is allowed in debug builds only. A release build needs the HTTPS address of the VM.
- Run `adb reverse` again each time you reconnect the phone.
- Demo posts are around 12.9716, 77.5946. To see them on a phone elsewhere, restart the API with `SEED_LAT` / `SEED_LNG` set to your location on a fresh database, or post from the app where you stand.

What the app does today:
- **Here** (home tab, no sign-in needed): posts within 20 m of you, **newest first**, as a **3-column grid of previews** (tap one to open a **full-screen viewer** and swipe up or down through the rest), with a colour-coded GPS badge ("GPS ±8 m"), filter chips (All / Photo / Video / Audio / Text, with counts) and distance and age on every post ("4 m away · 2 min ago"). Video and audio play in the viewer (tap play; only one plays at a time) and text posts show their words. It checks for new posts every 30 s and while you walk; new ones wait behind a "2 new posts" banner so the list does not jump while you read. The viewer's "…" menu has **Report this post**. An empty spot says "Nothing here yet" with a **Post here** button. The first time, a short note explains why the location is needed before Android asks.
- **The + button** (middle of the bottom bar, asks you to sign in first): a sheet with the GPS status and four big buttons, **Photo**, **Video**, **Audio** and **Text**. Each opens its own page: Photo and Video go straight to the camera (video up to 30 s, 50 MB, or from the gallery), Audio records up to 60 s in the app, Text is up to 1000 characters. Audio and video can be previewed before posting. The GPS line turns amber when weak and red when too weak to post (worse than 100 m). A moderator approves the post first.
- **Me** (second tab): your account, **Sign out**, and **My posts** newest first with review status and rejection reason.
- Not built yet: a map view, picking an existing audio file, author names on posts, push notifications, iOS testing.

Tests: `flutter analyze` and `flutter test` in `mobile/`.

## Deploy to a GCP VM

See [infra/prod/README.md](infra/prod/README.md): one VM running Docker Compose (database, API, Caddy with the admin panel), reached by the VM's IP address (plain HTTP, or experimental HTTPS on the IP), with nightly backups.

## Sample files

`samples/` has test files for the New post page and the API: `images/` (18 labelled PNG photos), `audio/` (WAV, M4A, MP3) and `video/` (three short MP4 clips). Made with ffmpeg and a small generator, so there are no copyright concerns.

`samples/load-samples.ps1` adds sample posts around one or more locations through the API, so it also works on a real server (where the `dev` demo data must not be used). It signs in as an admin you name (asking for the password, never storing it), creates three sample creators with random throw-away passwords, and skips a location that already has samples:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass     # this window only
cd C:\Projects\geo-app\samples
.\load-samples.ps1 -BaseUrl http://YOUR_VM_IP -AdminEmail you@example.com -Location '12.37602,77.06316','12.9786,77.364'
```

The first location gets the full set (13 approved within 20 m, 8 farther away, 9 pending, 2 rejected, 2 reports, including text posts); each further location gets a smaller one. On a server that was filled before text posts existed, add `-TextOnly` to add just the four text posts.

## API summary

| Method and path | Who |
|---|---|
| `POST /api/auth/register`, `/login`, `/refresh`, `/logout` | public |
| `GET /api/auth/me` | logged in |
| `GET /api/posts/nearby?lat=&lng=&radius=` | public (approved posts only, newest first, radius capped at 100 m) |
| `POST /api/posts` (multipart: `lat`, `lng`, `accuracy`, then either `file` + optional `caption`, or `text` with no file) | logged in; admin posts publish at once, others wait for review |
| `GET /api/posts/mine`, `POST /api/posts/{id}/report` | logged in |
| `GET /api/admin/posts?status=`, `POST /api/admin/posts/{id}/review` | admin |
| `GET /api/admin/users`, `PATCH /api/admin/users/{id}` | admin |

## Tests

```powershell
cd api
mvn test        # starts a throwaway PostGIS container, so Docker must be running
```

## Configuration

| Variable | Purpose | Default |
|---|---|---|
| `DB_URL`, `DB_USER`, `DB_PASSWORD` | database | local docker-compose values |
| `APP_JWT_SECRET` | token signing key, 32+ characters | development value, **change outside dev** |
| `APP_STORAGE_DIR` | where uploads are written | `./data/uploads` |
| `APP_ADMIN_EMAIL`, `APP_ADMIN_PASSWORD` | creates the first admin if missing | unset |
| `SEED_LAT`, `SEED_LNG` | centre for demo posts (dev profile) | 12.9716, 77.5946 |

## Known gaps for later

- Pending and rejected media files are reachable by anyone who knows the random file URL (they are not guessable, but not access controlled).
- No rate limiting on login or upload yet.
- No video/audio transcoding, push notifications, phone OTP, or admin view of reports.

## Preview images

The API makes a small JPEG preview (480 px wide) of every photo and video with ffmpeg, which the app's grid uses. The Docker image installs ffmpeg; locally set `APP_FFMPEG_PATH` if it is not on the PATH. A post is still created if the preview fails. For posts made before previews existed, sign in as admin and call `POST /api/admin/thumbnails` (up to 200 posts per call; repeat while `created` is above 0).
