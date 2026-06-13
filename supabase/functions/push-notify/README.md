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
