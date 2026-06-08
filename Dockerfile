# --- Build stage ---
FROM ghcr.io/cirruslabs/flutter:3.41.5 AS build

WORKDIR /app
COPY . .

ARG SUPABASE_URL=https://supabase.mangopos.do
ARG SUPABASE_ANON_KEY=eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.eyJpc3MiOiJzdXBhYmFzZSIsImlhdCI6MTc3MjgzOTUwMCwiZXhwIjo0OTI4NTEzMTAwLCJyb2xlIjoiYW5vbiJ9.LHw1pkCZ3DySAmly08hFoykgbG0CCC7k7Igh2izbCAg

# Identificador único de build. Si no se pasa, se usa la marca de tiempo del
# build, de modo que cada despliegue produce un valor distinto que la web
# detecta para mostrar el banner de "nueva versión disponible".
ARG BUILD_ID

RUN BUILD_ID="${BUILD_ID:-$(date +%s)}" && \
    flutter pub get && \
    flutter build web --release \
      --dart-define=SUPABASE_URL=$SUPABASE_URL \
      --dart-define=SUPABASE_ANON_KEY=$SUPABASE_ANON_KEY \
      --dart-define=BUILD_ID=$BUILD_ID && \
    echo "{\"build_id\":\"$BUILD_ID\"}" > build/web/app_version.json

# --- Production stage ---
FROM nginx:alpine

COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=build /app/build/web /usr/share/nginx/html

EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]
