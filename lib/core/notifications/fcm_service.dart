import 'dart:developer' as dev;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../firebase_options.dart';
import 'local_notification_helper.dart';

/// Background/terminated message handler. Must be a top-level function annotated
/// with `@pragma('vm:entry-point')` — it runs in its own isolate, so Firebase
/// has to be initialized again here. Notification-type messages are shown by the
/// OS automatically; this is mostly a hook for data payloads.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  } catch (_) {
    // Nothing to do — OS already shows notification-type messages.
  }
}

/// Firebase Cloud Messaging integration: registers the device token in Supabase
/// (`device_tokens`) so the backend can push to it, and shows foreground pushes
/// through the existing [LocalNotificationHelper].
///
/// Everything is best-effort and guarded: if Firebase isn't configured yet
/// (missing `google-services.json` / `GoogleService-Info.plist`) the app keeps
/// running normally — push just stays off until the native config is added.
class FcmService {
  FcmService._();

  static bool _ready = false;

  /// Initializes Firebase + FCM handlers. Call once at startup. No-op on web
  /// (web push needs a service worker + VAPID key, out of scope here).
  static Future<void> initialize() async {
    if (kIsWeb) return;
    try {
      await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

      await FirebaseMessaging.instance.requestPermission();

      // Foreground messages aren't shown automatically on Android — surface them
      // through the local-notifications channel we already use.
      FirebaseMessaging.onMessage.listen((message) {
        final n = message.notification;
        if (n == null) return;
        LocalNotificationHelper.show(
          title: n.title ?? 'Mango Dashboard',
          body: n.body ?? '',
        );
      });

      _ready = true;
    } catch (e, st) {
      dev.log('FCM init skipped (Firebase not configured?): $e',
          name: 'fcm', error: e, stackTrace: st);
    }
  }

  /// Registers (and keeps refreshed) this device's token in Supabase for the
  /// authenticated user + [businessId]. Best-effort; safe to call repeatedly.
  static Future<void> registerToken({required String businessId}) async {
    if (!_ready) return;
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null) await _upsert(token, businessId);
      FirebaseMessaging.instance.onTokenRefresh.listen((t) => _upsert(t, businessId));
    } catch (e) {
      dev.log('FCM token registration skipped: $e', name: 'fcm');
    }
  }

  /// Removes this device's token (call on sign-out so a logged-out phone stops
  /// receiving the business's pushes).
  static Future<void> unregisterToken() async {
    if (!_ready) return;
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token == null) return;
      await Supabase.instance.client.from('device_tokens').delete().eq('token', token);
    } catch (_) {
      // Offline / table missing — ignore.
    }
  }

  static Future<void> _upsert(String token, String businessId) async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;
    try {
      await Supabase.instance.client.from('device_tokens').upsert({
        'token': token,
        'user_id': userId,
        'business_id': businessId,
        'platform': defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android',
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }, onConflict: 'token');
    } catch (e) {
      // Table not created yet, RLS, or offline — push just won't target this
      // device until the backend table exists.
      dev.log('device_tokens upsert skipped: $e', name: 'fcm');
    }
  }
}
