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

### Supabase Database Schema

#### Core Tables

**businesses** — Business/restaurant entity. Has `id`, `name`, fiscal settings.

**user_businesses** — Many-to-many: users ↔ businesses. Columns: `user_id`, `business_id`, `role` (member_role enum: owner|admin|manager|staff|viewer), `branch_name`, `is_active`.

**profiles** — User profile data: `id` (FK → auth.users), `full_name`.

#### Order Flow

**dining_tables** — Physical tables: `id`, `zone_id` (FK → zones), `name`, `status`.

**zones** — Table zones/areas: `id`, `business_id`, `name`.

**table_sessions** — Dining session (one per table occupancy):
- `id`, `table_id` (FK → dining_tables), `business_id` (denormalized), `opened_by`, `opened_at`, `closed_at`
- `origin` (order_origin enum: dine_in|manual|quick|delivery|self_service)
- `waiter_user_id`, `people_count`, `customer_name`

**orders** — Sales orders:
- `id`, `session_id` (FK → table_sessions), `status_ext` (order_status enum: open|sent_to_kitchen|partially_paid|paid|void)
- `subtotal`, `discounts`, `service_fee`, `tax`, `total` (all numeric(12,2))
- `created_at`, `closed_at`

**order_items** — Line items:
- `id`, `order_id` (FK → orders, CASCADE), `check_id` (FK → order_checks, SET NULL)
- `product_id`, `product_name`, `qty` numeric(10,3), `unit_price` numeric(10,2)
- `subtotal`, `discounts`, `tax` numeric(12,2), `tax_mode` (exclusive|inclusive)
- `status` (item_status enum: pending|preparing|ready|served|void|draft|paid)

**order_checks** — Split bill support (max 5 per order):
- `id`, `order_id` (FK → orders, CASCADE), `label`, `position` (1-5)
- `subtotal`, `discounts`, `tax`, `total`, `is_closed`, `closed_at`

#### Payment & Cash Register

**payment_methods** — Per-business payment types:
- `id`, `business_id`, `name` (e.g. 'Efectivo'), `code` (cash|card|transfer)
- `is_active`, `requires_reference`, `icon`, `position`

**payments** — Individual payment records:
- `id`, `business_id` (FK → businesses), `order_id` (FK → orders), `check_id` (FK → order_checks)
- `payment_method_id` (FK → payment_methods) — determines cash/card/transfer
- `session_id` (FK → cash_register_sessions) — links payment to active cash session
- `amount` numeric, `change_amount` numeric DEFAULT 0
- `status` (pending|completed|refunded|cancelled)
- `processed_by` (FK → auth.users), `customer_id`, `customer_rnc`
- `fiscal_document_id` (FK → fiscal_documents)
- `created_at`

**cash_registers** — Physical cash register devices:
- `id`, `business_id`, `name`, `is_active`

**cash_register_sessions** — Cash drawer session (one per user per register):
- `id`, `cash_register_id` (FK → cash_registers), `user_id` (FK → auth.users)
- `opened_at`, `closed_at`, `start_amount` numeric(15,2), `end_amount` numeric(15,2)
- `difference` numeric(15,2), `status` (open|closed), `notes`

**cash_transactions** — Cash drawer movements (cash-only, not card/transfer):
- `id`, `session_id` (FK → cash_register_sessions)
- `amount` numeric(15,2), `type` (sale|deposit|withdrawal|expense)
- `description`, `related_order_id` (FK → orders), `created_at`
- Note: `type='sale'` only records **cash** portion (amount minus change). Card/transfer payments do NOT create cash_transactions.

#### Fiscal (Dominican Republic - DGII)

**fiscal_documents** — NCF/e-CF tax receipts:
- `id`, `business_id`, `order_id`, `payment_id`
- `ncf_type` (B01|B02|B14|B15|B16|E31-E45), `ncf_number`
- `customer_rnc`, `customer_name`, `subtotal`, `itbis_amount`, `total`
- `status` (active|cancelled|modified), `ecf_status` (pending|sent|accepted|rejected)

#### Key Relationships

```
payments.session_id → cash_register_sessions.id (links payment to cash session)
payments.payment_method_id → payment_methods.id (determines cash/card/transfer)
payments.order_id → orders.id → table_sessions.business_id (scopes to business)
cash_transactions.session_id → cash_register_sessions.id (cash-only movements)
```

#### Important RPC Functions

- **fn_process_payment_v3** — Processes payment: inserts into `payments`, creates `cash_transaction` (only for cash payments), marks items paid, closes order if fully paid. Requires `p_cashier_session_id`.
- **fn_open_cash_session** — Opens cash drawer session. One session per user per register.
- **fn_close_cash_session** — Closes session, calculates expected vs actual amounts. Returns breakdown: `expected_cash`, `expected_card`, `expected_transfer`, `expected_total`, `difference`.
- **fn_get_cash_session_summary** — Non-mutating summary with payment method breakdown from `payments` table (not just cash_transactions).

### Deployment

Web build is containerized: Flutter build stage -> nginx alpine serving the SPA with gzip and cache headers. Environment variables are baked in at build time via `--dart-define` build args in the Dockerfile.
