# Push notifications (FCM) — setup

The Flutter client (FcmService) registers each device's FCM token in
`device_tokens`. This Edge Function sends a push to a business's devices when
an event happens. Events: producto eliminado después de cocina, orden/venta
anulada (via `notification_events`, see section 7), cierre de caja, caja
descuadrada.

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
- Database Webhook (Dashboard → Database → Webhooks) as HTTP POST to the
  `push-notify` function, default Supabase payload:
  - table `cash_register_sessions`, events: UPDATE
  - (NO webhook on `order_items` any more — anulaciones go through
    `notification_events`, section 7. The function ignores order_items
    payloads; delete that webhook if it still exists.)

## 5. Test
With the app fully closed, remove a product that was already sent to the
kitchen, void an order, or close a cash session → the push should arrive.

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

## 7. Anulaciones y productos quitados (`notification_events`)

Migración `supabase/migrations/20261007_0001_notification_events.sql` (idéntica
en `mangospos`; prueba local `mangospos/supabase/tests/notification_events_local_test.sh`).

- Regla: si el producto salió a cocina, quitarlo o bajarle la cantidad AVISA,
  sin importar quién ni por dónde (mesa, subcuenta, caja cliente del Hub, cola
  offline, otra app, Studio). Lo que nunca salió a cocina no avisa.
- Triggers en la base deciden qué avisa y escriben una fila en
  `notification_events`:
  - `order_items` DELETE (por sentencia) y bajada de `qty`/`quantity` de un
    ítem enviado. Se mira `order_items` directamente (no `order_item_removals`,
    que no ve las reducciones sin etiqueta del Hub/cola offline); ese registro
    solo aporta motivo, operador y quién autorizó. Lo de la misma orden y la
    misma cuenta en 5 s se junta en un aviso. Solo se excluyen las RPC que
    redistribuyen cantidades (dividir cuenta, mover a subcuenta, transferir
    mesa): `private.fn_notif_is_rewrite`.
  - orden anulada con algo en cocina → "Orden anulada"; venta cobrada anulada
    → "Venta anulada" (uno por orden). Mesa vacía liberada → sin aviso.
  - anulación parcial (una subcuenta / un NCF) → "Venta anulada".
  - cortesía o descuento que pone una persona (20261020_0003) → "Cortesía" /
    "Descuento aplicado"; un descuento repartido en la cuenta es un solo
    aviso. Promos automáticas y ofertas no avisan.
- El INSERT llama a esta función por `pg_net` con
  `{"kind":"notification_event","event_id":…}` y el bearer service_role de
  `private.dashboard_cron_config` (sección 6; sin esa config no hay push, pero
  el aviso dentro de la app sí funciona y la migración lo advierte).
- La función espera 6 s, reserva el evento (`pushed_at`, nunca sale dos veces),
  pide el texto final a `fn_notification_event_refresh` y envía con
  `data.event_id` para que la app no muestre el mismo aviso dos veces.
- Reintento: el cron `notification_events_push_retry` (cada 2 min) manda
  `{"kind":"notification_event_sweep"}` si hay avisos de más de 1 minuto sin
  `pushed_at` (llamada perdida, función reiniciando).
- Preferencias: `item_voided` (producto eliminado o reducido), `order_voided`
  (orden o venta anulada), `item_courtesy` (cortesía) e `item_discount`
  (descuento). Tipos nuevos no requieren redeploy: la función toma título,
  cuerpo y clave de la fila.
- La migración elimina el trigger viejo `push_order_item_void` (un push por
  cada ítem en 'void').
