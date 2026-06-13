import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'core/network/supabase_bootstrap.dart';
import 'core/notifications/fcm_service.dart';
import 'core/notifications/local_notification_helper.dart';
import 'core/observability/error_reporter.dart';

Future<void> main() async {
  // Run inside a guarded zone so uncaught async errors are captured too.
  runZonedGuarded(() async {
    final widgetsBinding = WidgetsFlutterBinding.ensureInitialized();
    FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);

    // Framework errors (build/layout/paint). Keep the default console dump,
    // then forward to the reporter.
    final defaultOnError = FlutterError.onError;
    FlutterError.onError = (details) {
      defaultOnError?.call(details);
      ErrorReporter.report(
        details.exception,
        details.stack,
        context: details.context?.toString(),
      );
    };
    // Uncaught errors that bubble to the engine (e.g. failed platform calls).
    widgetsBinding.platformDispatcher.onError = (error, stack) {
      ErrorReporter.report(error, stack, fatal: true);
      return true; // handled — don't hard-crash the app
    };

    await SupabaseBootstrap.initialize();
    try {
      await LocalNotificationHelper.initialize();
    } catch (_) {
      // Notifications not available on this platform — continue without them.
    }
    // Firebase Cloud Messaging (push outside the app). Guarded internally — a
    // missing native config just leaves push off, the app still runs.
    await FcmService.initialize();

    runApp(const ProviderScope(child: MangoDashboardApp()));

    // Remove splash after the first frame is painted
    WidgetsBinding.instance.addPostFrameCallback((_) {
      FlutterNativeSplash.remove();
    });
  }, (error, stack) {
    ErrorReporter.report(error, stack, fatal: true);
  });
}
