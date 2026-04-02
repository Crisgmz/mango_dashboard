# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Mango Dashboard is a Flutter admin dashboard for the MangoPOS restaurant/business management system. It connects to a self-hosted Supabase backend to display sales KPIs, live orders, top products, and business analytics. The app targets web (deployed via Docker/nginx) and mobile (Android/iOS).

## Common Commands

```bash
# Install dependencies
flutter pub get

# Run in debug (Chrome)
flutter run -d chrome

# Run with custom Supabase config
flutter run --dart-define=SUPABASE_URL=https://... --dart-define=SUPABASE_ANON_KEY=...

# Build for web release
flutter build web --release --dart-define=SUPABASE_URL=https://supabase.mangopos.do --dart-define=SUPABASE_ANON_KEY=...

# Analyze code
flutter analyze

# Run tests
flutter test

# Run a single test file
flutter test test/widget_test.dart

# Docker build (web deployment)
docker build -t mango-dashboard .
```

## Architecture

### Layer Structure (lib/)

- **`env/`** — Compile-time environment config via `--dart-define`. `Env` class reads `SUPABASE_URL` and `SUPABASE_ANON_KEY`.
- **`core/`** — Shared utilities: Supabase initialization (`supabase_bootstrap.dart`), role normalization (`role_mapper.dart`), number/currency formatters, DPI scaling.
- **`domain/`** — Immutable data models. No framework dependencies beyond `@immutable`.
  - `auth/` — `AdminAccessProfile`, `AdminBusinessMembership` (multi-business support)
  - `dashboard/` — `DashboardSummary`, `TopProduct`, `LiveOrderItem`, `HourlySale`, `TicketItem`, etc.
- **`data/`** — Supabase query services. Each service takes a `SupabaseClient` via constructor injection.
  - `AdminAccessService` — Auth, role resolution, multi-business switching
  - `DashboardDataService` — Aggregates sales, orders, products with batched `inFilter` queries to avoid URI-too-long errors
- **`app/`** — App entry point and DI. `providers.dart` wires Riverpod providers for Supabase client and services.
- **`presentation/`** — UI layer organized by feature:
  - `auth/` — Login view and auth gate view model
  - `dashboard/` — Main dashboard: root view, KPI cards, sales chart (fl_chart), top products, top seller widgets
  - `splash/` — Animated splash screen
  - `theme/` — Light/dark theme with `ThemeController` (persisted via SharedPreferences)

### State Management

Uses **Riverpod** (`flutter_riverpod`). Key providers are in `app/di/providers.dart`. ViewModels are `StateNotifier`-based or `AsyncNotifier`-based in the `viewmodel/` directories.

### Auth & Multi-Business

Users authenticate via Supabase Auth (email/password, PKCE flow). Access is resolved through the `user_businesses` table joined with `businesses`. Only users with `owner` or `admin` roles (checked by `isAdminDashboardRole`) can access the dashboard. Users can switch between businesses they belong to.

### Supabase Tables Referenced

`payments`, `orders`, `table_sessions`, `dining_tables`, `order_items`, `menu_items`, `categories`, `user_businesses`, `businesses`

### Deployment

Web build is containerized: Flutter build stage -> nginx alpine serving the SPA with gzip and cache headers. Environment variables are baked in at build time via `--dart-define` build args in the Dockerfile.
