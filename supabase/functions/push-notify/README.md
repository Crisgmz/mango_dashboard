# Push notifications (FCM) — setup

The Flutter client (FcmService) registers each device's FCM token in
`device_tokens`. This Edge Function, triggered by Database Webhooks, sends a
push to a business's devices when an event happens. Events: producto anulado,
cierre de caja, caja descuadrada.

## 1. Firebase project + app config
- Create (or reuse) a Firebase project.
- Easiest: `dart pub global activate flutterfire_cli` then `flutterfire configure`
  — registers Android + iOS and drops the native config files. (Also generates
  `firebase_options.dart`; not required since we call `Firebase.initializeApp()`
  with the native files, but harmless.)
- Manual alternative:
  - `android/app/google-services.json`
  - `ios/Runner/GoogleService-Info.plist` (add via Xcode so it's in the target)

## 2. Android gradle (skip if you ran `flutterfire configure`)
- `android/settings.gradle.kts` plugins: `id("com.google.gms.google-services") version "4.4.2" apply false`
- `android/app/build.gradle.kts` plugins: `id("com.google.gms.google-services")`
- Build breaks until `google-services.json` exists — add it first.

## 3. iOS (APNs — required, push won't work without it)
- Xcode → Runner target → Signing & Capabilities → add **Push Notifications**
  and **Background Modes → Remote notifications**.
- Apple Developer → create an **APNs Auth Key (.p8)** → upload it in Firebase
  Console → Project Settings → Cloud Messaging → APNs.

## 4. Backend
- Apply `supabase/migrations/20260613_device_tokens.sql` (adjust `business_id`
  type if your `businesses.id` isn't uuid).
- Deploy: `supabase functions deploy push-notify`
- Secrets:
  - `supabase secrets set FCM_PROJECT_ID=<your-firebase-project-id>`
  - `supabase secrets set FCM_SERVICE_ACCOUNT='<service-account-json>'`
    (Firebase Console → Project Settings → Service accounts → Generate new
    private key → paste the whole JSON.)
- Database Webhooks (Dashboard → Database → Webhooks), both as HTTP POST to the
  `push-notify` function, default Supabase payload:
  - table `order_items`, events: UPDATE
  - table `cash_register_sessions`, events: UPDATE

## 5. Test
With the app fully closed, void an item or close a cash session → the push
should arrive on the phone.

## 6. Billing reminders (push de cobro próximo)

Además de los eventos por webhook, un job diario empuja recordatorios de cobro
(cobro próximo, fin de prueba, pago vencido, suspensión). Lógica: migración
`supabase/migrations/20260617_billing_reminders_push.sql`.

- Flujo: `pg_cron` (13:00 UTC) → `private.fn_run_billing_reminders()` →
  `net.http_post` a esta función con `{"kind":"billing_reminder_sweep"}` y el
  bearer service_role → la función llama a `fn_billing_reminders_due()` (quién +
  mensaje) y hace fan-out a `device_tokens`.
- Requiere extensiones `pg_net` y `pg_cron` (ya usadas por el cron de Azul).
- **Configurar una vez** la URL base + service_role key (el mismo que ve la
  función en `SUPABASE_SERVICE_ROLE_KEY`):

  ```sql
  insert into private.dashboard_cron_config (functions_base_url, service_role_key)
  values ('https://supabase.mangopos.do/functions/v1', '<SERVICE_ROLE_KEY>')
  on conflict (id) do update
    set functions_base_url = excluded.functions_base_url,
        service_role_key   = excluded.service_role_key,
        updated_at = now();
  ```

- Redeploy de la función tras este cambio: `supabase functions deploy push-notify`.
- Probar manualmente sin esperar al cron:
  `select private.fn_run_billing_reminders();`
  (o ver a quién avisaría hoy: `select * from public.fn_billing_reminders_due();`).
- Offsets: cobro/fin de prueba avisan 5 y 1 días antes; `past_due`/`suspended`
  avisan cada día. Cambiar el umbral con el parámetro `p_days`.
