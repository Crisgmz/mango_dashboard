import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../presentation/theme/theme_controller.dart';
import '../presentation/theme/theme_data_factory.dart';
import '../presentation/dashboard/view/dashboard_root_view.dart';
import '../presentation/splash/view/mango_splash_screen.dart';

class MangoDashboardApp extends ConsumerStatefulWidget {
  const MangoDashboardApp({super.key});

  @override
  ConsumerState<MangoDashboardApp> createState() => _MangoDashboardAppState();
}

class _MangoDashboardAppState extends ConsumerState<MangoDashboardApp> {
  bool _showSplash = true;

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(themeModeProvider);

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Mango Dashboard',
      themeMode: themeMode,
      theme: MangoThemeFactory.lightTheme,
      darkTheme: MangoThemeFactory.darkTheme,
      home: _showSplash
          ? MangoSplashScreen(onComplete: () => setState(() => _showSplash = false))
          : const DashboardRootView(),
    );
  }
}
