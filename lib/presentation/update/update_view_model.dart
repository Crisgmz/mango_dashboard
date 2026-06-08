import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/update/update_service.dart';
import '../../env/env.dart';

/// Expone `true` cuando el servidor publica un `build_id` distinto al build
/// con el que se cargó esta sesión, indicando que hay una nueva versión.
final updateAvailableProvider =
    StateNotifierProvider<UpdateController, bool>((ref) {
  final controller = UpdateController();
  controller.start();
  ref.onDispose(controller.dispose);
  return controller;
});

class UpdateController extends StateNotifier<bool> {
  UpdateController() : super(false);

  /// Cada cuánto se consulta `version.json`.
  static const _pollInterval = Duration(minutes: 2);

  Timer? _timer;

  void start() {
    // Solo tiene sentido en web y cuando hay un build id real (no en dev).
    if (!kIsWeb || Env.buildId == 'dev') return;

    // Primera comprobación tras un breve margen para no competir con el
    // arranque, y luego de forma periódica.
    Future<void>.delayed(const Duration(seconds: 10), _check);
    _timer = Timer.periodic(_pollInterval, (_) => _check());
  }

  Future<void> _check() async {
    if (state) return; // Ya se detectó: no hace falta seguir consultando.
    final remote = await fetchRemoteBuildId();
    if (remote == null) return;
    if (remote != Env.buildId) {
      state = true;
    }
  }

  /// Recarga la app para aplicar la nueva versión.
  void applyUpdate() => reloadApp();

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
