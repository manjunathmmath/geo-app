# Deploying GeoApp to one GCP VM (using the VM's IP address)

Everything runs in three containers on one VM: **db** (PostgreSQL + PostGIS), **api** (Spring Boot) and
**caddy** (web server; also serves the admin panel and the uploaded media). Nothing else is needed.

```
phone / browser --80/443--> caddy --/api--> api --> db
                              |--/media--> uploads volume (shared with api)
                              |--/-------> admin panel (static files built into the caddy image)
```

## Two modes (the `CADDYFILE` setting in `.env`)

| Mode | `CADDYFILE` | Use it for |
|---|---|---|
| Plain HTTP on the IP | `Caddyfile.http` | First test. Works today. Passwords and login tokens are **not encrypted** on the network, so use throwaway passwords. |
| HTTPS on the IP (experimental) | `Caddyfile.https-ip` | Uses a Let's Encrypt short-lived IP certificate (valid about 6.5 days, renewed automatically). The syntax is accepted by Caddy 2.11, but issuing a certificate can only be proven on the real VM. If it fails, read `docker compose logs caddy` and switch back to the HTTP file. |

Android phones need nothing special for HTTPS-on-IP (Let's Encrypt is trusted). iPhones cannot use plain HTTP at all.

## 1. Create the VM (once, from your PC)

Install the Google Cloud CLI (`gcloud`), sign in, and choose your project. Pick the region closest to your users; the
commands below use Mumbai (`asia-south1`) as an example. Prices vary, so check the GCP pricing calculator first.

```powershell
gcloud auth login
gcloud config set project YOUR_PROJECT_ID

# A static external IP, so the address never changes (also needed for the HTTPS certificate)
gcloud compute addresses create geoapp-ip --region=asia-south1
gcloud compute addresses describe geoapp-ip --region=asia-south1 --format="get(address)"

# Allow web traffic to machines that carry the "geoapp-web" tag
gcloud compute firewall-rules create geoapp-web --direction=INGRESS --allow=tcp:80,tcp:443 --target-tags=geoapp-web --source-ranges=0.0.0.0/0

# The VM: 2 vCPU, 4 GB RAM, 50 GB disk
gcloud compute instances create geoapp --zone=asia-south1-a --machine-type=e2-medium `
  --image-family=debian-12 --image-project=debian-cloud --boot-disk-size=50GB --boot-disk-type=pd-balanced `
  --address=geoapp-ip --tags=geoapp-web
```

Do not open port 5432 (the database) or 8080 (the API): only Caddy is exposed. The default SSH rule allows any address;
consider restricting it to your own IP in the GCP console.

## 2. Install Docker on the VM

```powershell
gcloud compute ssh geoapp --zone=asia-south1-a
```
Then, on the VM:
```bash
curl -fsSL https://get.docker.com | sudo sh       # Docker's official install script
sudo usermod -aG docker $USER && exit              # log in again so the group applies
```

## 3. Copy the project to the VM

From `C:\Projects\geo-app` on your PC (the mobile app is not needed on the server):

```powershell
cd C:\Projects\geo-app
tar --exclude=node_modules --exclude=target --exclude=build --exclude=dist --exclude=data --exclude=.dart_tool --exclude=mobile --exclude=.env -czf $env:TEMP\geoapp.tgz api admin-web infra .dockerignore
gcloud compute scp $env:TEMP\geoapp.tgz geoapp:~ --zone=asia-south1-a
```

## 4. Configure and start

```powershell
gcloud compute ssh geoapp --zone=asia-south1-a
```
On the VM:
```bash
mkdir -p geoapp && tar xzf geoapp.tgz -C geoapp && cd geoapp/infra/prod
cp .env.example .env
nano .env            # set PUBLIC_IP, the passwords, and the admin email. Make secrets with:  openssl rand -base64 48
docker compose up -d --build     # the first build takes several minutes
docker compose ps                # all three should be "running" (db "healthy")
curl http://localhost/actuator/health     # {"status":"UP"}
```

Open `http://YOUR_VM_IP/` in a browser: that is the admin panel. Sign in with `APP_ADMIN_EMAIL` / `APP_ADMIN_PASSWORD` from `.env`.

**Do not run the server with the `dev` profile.** It creates demo accounts with passwords that are public in this repository, which on an internet-facing machine would hand out an admin login. The server starts with only the admin you configure; creators register in the app.

## 5. Point the mobile app at the VM

The server address is fixed into the app when it is built. From `C:\Projects\geo-app\mobile` on your PC:

```powershell
# HTTP mode: the debug build is the one that allows plain http:// on Android
flutter build apk --debug --dart-define=API_BASE=http://YOUR_VM_IP
# HTTPS mode: a normal release build
flutter build apk --release --dart-define=API_BASE=https://YOUR_VM_IP
```
The APK is in `mobile\build\app\outputs\flutter-apk\`. Copy it to the other phone and install it (allow "install unknown apps" for the app you open it from).

## 6. Backups (important on a single VM)

```bash
chmod +x backup.sh
./backup.sh                                   # writes a database dump and an uploads archive to ~/geoapp-backups
# Copy them off the VM too, for example to a Cloud Storage bucket:
GCS_BUCKET=my-geoapp-backups ./backup.sh
```
Run it nightly with `crontab -e`:
```
30 2 * * * cd /home/YOUR_USER/geoapp/infra/prod && GCS_BUCKET=my-geoapp-backups ./backup.sh >> /var/log/geoapp-backup.log 2>&1
```
Restore (stop the API first with `docker compose stop api`):
```bash
docker compose exec -T db pg_restore -U geoapp -d geoapp --clean --if-exists < ~/geoapp-backups/db-STAMP.dump
docker run --rm -v geoapp_uploads:/data -v ~/geoapp-backups:/backup alpine tar xzf /backup/uploads-STAMP.tgz -C /data
docker compose start api
```
Try a restore once before you need it.

## Updating later

Copy the changed files again (step 3), then on the VM: `cd geoapp/infra/prod && docker compose up -d --build`. The database and
uploads live in Docker volumes, so they survive rebuilds. Do not run `docker compose down -v`: the `-v` deletes them.

## Handy commands

```bash
docker compose logs -f api          # API log
docker compose logs -f caddy        # web server / certificate log
docker compose restart caddy        # after changing CADDYFILE in .env: docker compose up -d
df -h /var/lib/docker               # disk space (uploads grow over time)
```

## Known limits of this setup

- One VM is one point of failure: the backups above are what protect your data.
- The admin panel is reachable by anyone who knows the IP; only the login protects it. Use a strong admin password.
- There is no rate limiting on login or upload yet, and pending media files are reachable by anyone with the exact random URL.
- Plain HTTP mode exposes passwords on the network. Treat it as a test setup.
