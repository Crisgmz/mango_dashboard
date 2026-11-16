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

## UI Design System (obligatorio para toda pantalla nueva)

Toda la UI del sistema sigue el estilo **"cards blandas"**: superficies planas color card, bordes de 1px, esquinas muy redondeadas, sin sombras fuertes ni tintes Material 3. Si algo se ve con fondo durazno/tinte del seed, es un bug de tema, no un estilo válido.

### Fuentes de verdad (nunca hardcodear)

- **Colores** — SIEMPRE vía `MangoThemeFactory` (`lib/presentation/theme/theme_data_factory.dart`). Prohibido usar colores literales (`Color(0xFF...)`, `Colors.orange`, etc.) en las vistas.
  - Marca: `MangoThemeFactory.mango` (naranja #F97316), `mangoDeep` para énfasis.
  - Semánticos: `success` (verde, `successDeep` para gradientes), `warning` (ámbar), `danger` (rojo), `info` (azul).
  - Métodos de pago: `payCard` (azul), `payTransfer` (morado); efectivo usa `success`. Estados apagados/fallback: `neutral`. Marca externa: `whatsapp`. Tooltips de gráficas: `tooltipBackground(context)`.
  - Por contexto (respetan light/dark): `cardColor(context)`, `borderColor(context)`, `altSurface(context)` (fondos de inputs/chips), `textColor(context)`, `mutedText(context)`.
- **Espaciado/tamaños** — SIEMPRE vía `DpiScale.of(context)`: `dpi.space(n)` para paddings/gaps, `dpi.radius(n)` para esquinas, `dpi.font(n)` para fuentes, `dpi.icon(n)` para íconos, `dpi.scale(n)` para dimensiones. Nunca números crudos en EdgeInsets/SizedBox.
- **Números/moneda** — SIEMPRE vía `MangoFormatters`: `.currency()` (RD$), `.number()`, `.percent()`. Nunca `toStringAsFixed` directo en UI.
- **Tipografía** — usar `Theme.of(context).textTheme` (headlineMedium 28/w700, titleLarge 22/w700, titleMedium 16/w600, bodyLarge 15, bodyMedium 14, bodySmall 13 muted) o `TextStyle` con `dpi.font(...)` + color del factory.
- **Dependencias** — no agregar paquetes nuevos sin aprobación explícita del usuario.

### Receta de la card blanda (el bloque base de todo)

```dart
Container(
  padding: EdgeInsets.all(dpi.space(14)),
  decoration: BoxDecoration(
    color: MangoThemeFactory.cardColor(context),
    borderRadius: BorderRadius.circular(dpi.radius(14)),
    border: Border.all(color: MangoThemeFactory.borderColor(context)),
  ),
  child: ...,
)
```
- Cards tocables: envolver en `Material(color: Colors.transparent)` + `InkWell` con el mismo borderRadius.
- Sin `elevation`, sin `BoxShadow` salvo el hero card naranja del hub.
- Filas de lista = cards con `margin: EdgeInsets.only(bottom: dpi.space(8))`, avatar de inicial (36x36, mango al 10% de alpha, radio 10) a la izquierda, título w700 13.5 + subtítulo muted 11, acción/ícono a la derecha.

### Componentes con tema global (NO estilizar a mano)

`MangoThemeFactory._build` ya define `DialogTheme`, `BottomSheetTheme`, `DatePicker/TimePickerTheme`, `Switch/Checkbox/RadioTheme`, `Filled/Elevated/Outlined/TextButtonTheme`, `PopupMenuTheme`, `SnackBarTheme`, `DropdownMenuTheme` y `ProgressIndicatorTheme` — todos con fondo card, `surfaceTintColor: transparent`, esquinas 24 (diálogos/sheets) o 14 (botones) y acento mango. Regla: usar los widgets estándar (`AlertDialog`, `showDatePicker`, `Switch`, `FilledButton`...) SIN pasar colores ni shapes; el tema hace el trabajo. Si un componente sale con el tinte M3, se arregla agregando su theme al factory, nunca parchando la vista.

### Patrones de pantalla

- **Bottom sheets de selección** — usar `showSoftItemPicker` (`lib/presentation/widgets/soft_item_picker_sheet.dart`): fondo scaffold, top radius 24, asa de arrastre, búsqueda con autofocus, resultados como cards blandas. Cualquier picker nuevo se hace con este widget o siguiendo su anatomía exacta; prohibido `ListTile` plano sobre fondo blanco.
- **Diálogos de edición** — `AlertDialog` estándar (hereda el tema): título = nombre de la entidad, campos con `labelText`, acciones `TextButton` (Cancelar) + `FilledButton` (acción principal).
- **Jerarquía de botones** — principal: `FilledButton` mango; secundario: `OutlinedButton`; terciario/enlace: `TextButton`; destructivo: mismo widget con `danger`. Acciones de header de sección: `TextButton.icon` compacto (ícono 16-18).
- **Barra inferior fija** — pantallas de creación (OC, recepción, transferencia) llevan resumen (subtotal · ITBIS · total w800) + botones pegados abajo, sobre `SafeArea`.
- **Headers de sección** — label MAYÚSCULAS pequeñas (11-12, w700, letterSpacing ~0.6, mutedText) con contador entre paréntesis y acciones a la derecha.
- **Semáforos de estado** — verde/ámbar/rojo con los semánticos del factory (stock: borde izquierdo 4px; margen: verde ≥30 / ámbar 15-29 / rojo <15).
- **Textos largos** — nombres de negocio/sucursal y subtítulos que pueden no caber usan `MarqueeText` (`lib/presentation/widgets/marquee_text.dart`), formato "Negocio - Sucursal".
- **Reportes (carga en segundo plano)** — nunca `FutureBuilder` con rueda a pantalla completa. Usar `ReportLoadController` (`presentation/dashboard/viewmodel/report_load_controller.dart`) con una clave de `reportCacheKey(...)` y pintar con `ReportBody` + `ReportStaleFade` en el encabezado (`presentation/dashboard/widgets/report_loading.dart`): barra de avance, esqueleto, lo anterior atenuado al cambiar de periodo, caché de 45 s / 5 min y cancelación al salir. En el servicio, toda consulta de reporte pasa por `_paginate` / `_batchedInFilter` o `ReportRequestThrottle.run` (`data/dashboard/report_load.dart`), que limitan las peticiones simultáneas.
- **Estados vacíos** — nunca una lista en blanco: ícono muted + título corto + una línea que enseñe qué hacer (y CTA si aplica).
- **Secciones no construidas** — no se listan en hubs/menús hasta estar funcionales (regla sin filas muertas).
- **Escáner de cámara** — todo flujo que agregue insumos (OC, recepción, conteos, búsqueda de stock, transferencias si aplica) ofrece `ReceptionScannerPage`: continuo (`onCode`, cada escaneo suma +1) o `captureOnce: true` para llenar un campo.
- **Feedback** — `SnackBar` estándar (flotante, tema global) para confirmaciones/errores de validación.

### Estructura de una feature nueva

`domain/<feature>/` (modelos inmutables) → `data/<feature>/` (servicio con `SupabaseClient` inyectado, tolerante a fallos con try/catch por carga) → `presentation/<feature>/viewmodel/` (Riverpod StateNotifier) → `presentation/<feature>/view/` (pantallas) + `widgets/` para piezas reutilizables. Pantallas de sección se PUSHEAN como `Scaffold` propio (no IndexedStack), con AppBar heredado del tema.
