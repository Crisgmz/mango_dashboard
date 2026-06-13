import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../env/env.dart';

/// Central sink for everything that crashes. Wired from `main.dart` via
/// `FlutterError.onError`, `PlatformDispatcher.onError` and `runZonedGuarded`.
///
/// Each error is:
///  1. always logged to the console (logcat / DevTools) with its stack trace, so
///     it is visible during development without extra setup; and
///  2. best-effort inserted into the Supabase `app_errors` table — failures
///     (table absent, offline, Supabase not yet initialized) are swallowed, so
///     this never throws and never makes a crash worse.
///
/// To turn on remote logging, create the table once on the backend:
///
/// ```sql
/// create table public.app_errors (
///   id          uuid primary key default gen_random_uuid(),
///   created_at  timestamptz not null default now(),
///   message     text,
///   context     text,
///   fatal       boolean default false,
///   stack       text,
///   platform    text,
///   app_version text
/// );
/// alter table public.app_errors enable row level security;
/// create policy app_errors_insert on public.app_errors
///   for insert to authenticated, anon with check (true);
/// ```
class ErrorReporter {
  ErrorReporter._();

  // Guards the remote send against re-entrancy / floods.
  static bool _sending = false;

  /// Records [error]. Safe to call from any isolate state; never throws.
  static void report(
    Object error,
    StackTrace? stack, {
    String? context,
    bool fatal = false,
  }) {
    developer.log(
      context == null ? '$error' : '$context: $error',
      name: 'mango',
      level: fatal ? 1000 : 900, // SEVERE : WARNING
      error: error,
      stackTrace: stack,
    );

    if (_sending) return;
    _sending = true;
    unawaited(
      _sendRemote(error, stack, context, fatal).whenComplete(() => _sending = false),
    );
  }

  static Future<void> _sendRemote(
    Object error,
    StackTrace? stack,
    String? context,
    bool fatal,
  ) async {
    try {
      await Supabase.instance.client.from('app_errors').insert({
        'message': '$error',
        'context': context,
        'fatal': fatal,
        'stack': stack?.toString(),
        'platform': kIsWeb ? 'web' : defaultTargetPlatform.name,
        'app_version': Env.buildId,
      });
    } catch (_) {
      // Table missing, offline, or Supabase not initialized — the local log
      // above is enough. Never let error reporting raise its own error.
    }
  }
}
