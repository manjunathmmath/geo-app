# Build context is the repository root (see docker-compose.yml).
# Stage 1 builds the React admin panel; stage 2 is Caddy with the built site and its config files.
FROM node:20-alpine AS admin
WORKDIR /app
COPY admin-web/package.json admin-web/package-lock.json ./
# --legacy-peer-deps: npm 10 crashes on Vite's optional peer dependencies without it.
RUN npm ci --legacy-peer-deps
COPY admin-web/ ./
RUN npm run build

FROM caddy:2
COPY infra/prod/caddy/Caddyfile.http infra/prod/caddy/Caddyfile.https-ip infra/prod/caddy/app.caddy /etc/caddy/
COPY --from=admin /app/dist /srv/admin
