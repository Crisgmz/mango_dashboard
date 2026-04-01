# --- Build stage ---
FROM ghcr.io/cirruslabs/flutter:3.41.5 AS build

WORKDIR /app
COPY . .

ARG SUPABASE_URL=https://supabase.mangopos.do
ARG SUPABASE_ANON_KEY=eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.eyJpc3MiOiJzdXBhYmFzZSIsImlhdCI6MTc3MjgzOTUwMCwiZXhwIjo0OTI4NTEzMTAwLCJyb2xlIjoiYW5vbiJ9.LHw1pkCZ3DySAmly08hFoykgbG0CCC7k7Igh2izbCAg

RUN flutter pub get && \
    flutter build web --release \
      --dart-define=SUPABASE_URL=$SUPABASE_URL \
      --dart-define=SUPABASE_ANON_KEY=$SUPABASE_ANON_KEY

# --- Production stage ---
FROM nginx:alpine

COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=build /app/build/web /usr/share/nginx/html

EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]
