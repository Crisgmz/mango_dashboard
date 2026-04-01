import 'package:flutter/material.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'core/network/supabase_bootstrap.dart';

Future<void> main() async {
  WidgetsBinding widgetsBinding = WidgetsFlutterBinding.ensureInitialized();
  FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);
  
  await SupabaseBootstrap.initialize();
  
  runApp(const ProviderScope(child: MangoDashboardApp()));
  
  // Remove splash after a small frame delay to ensure app is ready
  FlutterNativeSplash.remove();
}
