import 'dart:io';
import 'dart:ui';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';

class LocalNotificationHelper {
  LocalNotificationHelper._();

  static final _plugin = FlutterLocalNotificationsPlugin();
  static int _idCounter = 0;
  static bool _initialized = false;

  /// The Android channel id. Must match `default_notification_channel_id` in
  /// AndroidManifest.xml so OS-built pushes (app killed/background) use it too.
  static const _androidChannelId = 'mango_dashboard';

  static Future<void> initialize() async {
    const androidSettings = AndroidInitializationSettings('@mipmap/launcher_icon');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    const settings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );
    await _plugin.initialize(settings: settings);

    if (Platform.isAndroid) {
      // Create the high-importance channel up front. The OS needs it to post
      // notifications when the app is killed/background (Flutter code doesn't
      // run then). Done before requesting permission so the channel always
      // exists, even if the user grants the permission later.
      const channel = AndroidNotificationChannel(
        _androidChannelId,
        'Mango Dashboard',
        description: 'Notificaciones del dashboard',
        importance: Importance.high,
      );
      await _plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(channel);

      await Permission.notification.request();
    }
    _initialized = true;
  }

  static Future<void> show({
    required String title,
    required String body,
  }) async {
    if (!_initialized) return;
    try {
      final androidDetails = AndroidNotificationDetails(
        'mango_dashboard',
        'Mango Dashboard',
        channelDescription: 'Notificaciones del dashboard',
        importance: Importance.high,
        priority: Priority.high,
        icon: '@mipmap/launcher_icon',
        color: const Color(0xFFF59E0B),
      );
      const iosDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      );
      final details = NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      );
      await _plugin.show(id: _idCounter++, title: title, body: body, notificationDetails: details);
    } catch (_) {
      // Silently fail — in-app notifications still work via the bell icon.
    }
  }
}
