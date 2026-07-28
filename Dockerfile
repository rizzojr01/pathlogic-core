# --- Build stage: pinned Flutter, matches .fvm/fvm_config.json ---
FROM ghcr.io/cirruslabs/flutter:3.41.9 AS build
WORKDIR /app

COPY pubspec.yaml pubspec.lock ./
RUN flutter pub get

COPY . .
RUN flutter pub get \
 && flutter build web --release

# --- Runtime: nginx serving static build, respects $PORT ---
FROM nginx:alpine
COPY --from=build /app/build/web /usr/share/nginx/html
COPY nginx.conf.template /etc/nginx/templates/default.conf.template
ENV PORT=8080
EXPOSE 8080
