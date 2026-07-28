# --- Build stage: pinned Flutter, matches .fvm/fvm_config.json ---
FROM ghcr.io/cirruslabs/flutter:3.41.9 AS build
WORKDIR /app

# Build-time env vars. Set in Koyeb → Service → Environment variables (mark as
# "Build-time"). Any left blank stay empty in the bundled .env; app tolerates
# missing values (dotenv[...] ?? '').
ARG BASE_URL=""
ARG KOYEB_BASE_URL=""
ARG SENTRY_DSN=""

COPY pubspec.yaml pubspec.lock ./
RUN flutter pub get

COPY . .

# Generate .env from build args (.env is gitignored, so it's never in the
# repo — this is the only place values enter the bundle).
RUN printf 'BASE_URL=%s\nKOYEB_BASE_URL=%s\nSENTRY_DSN=%s\n' \
      "$BASE_URL" "$KOYEB_BASE_URL" "$SENTRY_DSN" > .env \
 && flutter pub get \
 && flutter build web --release

# --- Runtime: nginx serving static build, respects $PORT ---
FROM nginx:alpine
COPY --from=build /app/build/web /usr/share/nginx/html
COPY nginx.conf.template /etc/nginx/templates/default.conf.template
ENV PORT=8080
EXPOSE 8080
