import 'package:flutter/material.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'core/network/supabase_bootstrap.dart';
import 'core/notifications/local_notification_helper.dart';

Future<void> main() async {
  WidgetsBinding widgetsBinding = WidgetsFlutterBinding.ensureInitialized();
  FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);

  await SupabaseBootstrap.initialize();
  try {
    await LocalNotificationHelper.initialize();
  } catch (_) {
    // Notifications not available on this platform — continue without them.
  }
  
  runApp(const ProviderScope(child: MangoDashboardApp()));

  // Remove splash after the first frame is painted
  WidgetsBinding.instance.addPostFrameCallback((_) {
    FlutterNativeSplash.remove();
  });
}
