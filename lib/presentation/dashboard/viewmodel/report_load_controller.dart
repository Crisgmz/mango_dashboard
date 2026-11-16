import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../data/dashboard/report_load.dart';
import '../../../data/dashboard/report_result_cache.dart';

/// Estado de carga de UN reporte en pantalla, en segundo plano.
///
///  * Lo último que se cargó se queda en pantalla mientras llega lo nuevo
///    ([isStale] avisa que es de otro periodo, para atenuarlo).
///  * Cada carga nueva cancela la anterior: deja de pedir páginas y su
///    resultado, si llega tarde, se descarta (antes podía pisar al nuevo).
///  * Tocar periodos seguidos solo dispara el último ([debounce]).
///  * Lo reciente sale de [ReportResultCache] sin tocar el backend.
///  * Al cerrar la pantalla ([dispose]) la carga en curso se cancela.
///
/// [progress] va aparte para que solo la barra se redibuje con cada página.
class ReportLoadController<T> extends ChangeNotifier {
  ReportLoadController({this.debounce = const Duration(milliseconds: 300)});

  final Duration debounce;
  final ValueNotifier<ReportLoadProgress> progress =
      ValueNotifier(ReportLoadProgress.none);

  T? _data;
  String? _dataKey;
  String? _requestedKey;
  Object? _error;
  bool _loading = false;
  bool _started = false;
  bool _disposed = false;
  ReportLoadTicket? _ticket;
  Timer? _timer;
  Future<T> Function()? _lastFetch;

  T? get data => _data;
  bool get hasData => _dataKey != null;
  bool get isLoading => _loading;
  Object? get error => _error;

  /// Primera carga: todavía no hay nada que mostrar.
  bool get isFirstLoad => _loading && !hasData;

  /// Lo que hay en pantalla es de otro periodo; el pedido sigue en camino o
  /// falló.
  bool get isStale => hasData && _dataKey != _requestedKey;

  /// Datos que ya vinieron con la pantalla (p. ej. del dashboard) para el
  /// periodo [key]. No consulta nada.
  void seed(String key, T data) {
    _data = data;
    _dataKey = key;
    _requestedKey = key;
  }

  void load({
    required String key,
    required Future<T> Function() fetch,
    bool force = false,
  }) {
    if (_disposed) return;
    _timer?.cancel();
    _ticket?.cancel();
    _ticket = null;
    _requestedKey = key;
    _lastFetch = fetch;
    _error = null;

    if (!force) {
      final cached = ReportResultCache.read<T>(key);
      if (cached != null) {
        _data = cached.value;
        _dataKey = key;
        if (cached.isFresh) {
          _loading = false;
          notifyListeners();
          return;
        }
        // Viejo pero usable: se muestra ya y se refresca detrás.
      }
    }

    _loading = true;
    progress.value = ReportLoadProgress.none;
    notifyListeners();

    // La primera carga sale de inmediato; las demás esperan un momento por
    // si el usuario sigue cambiando de periodo.
    if (!_started) {
      _started = true;
      _run(key, fetch);
    } else {
      _timer = Timer(debounce, () => _run(key, fetch));
    }
  }

  /// Vuelve a pedir el último reporte sin pasar por la caché.
  void retry() {
    final key = _requestedKey;
    final fetch = _lastFetch;
    if (key == null || fetch == null) return;
    load(key: key, fetch: fetch, force: true);
  }

  Future<void> _run(String key, Future<T> Function() fetch) async {
    late final ReportLoadTicket ticket;
    ticket = ReportLoadTicket(onProgress: (p) {
      if (!_disposed && identical(_ticket, ticket)) progress.value = p;
    });
    _ticket = ticket;

    try {
      final result = await ticket.run(fetch);
      if (_disposed || !identical(_ticket, ticket)) return;
      ReportResultCache.write(key, result);
      _data = result;
      _dataKey = key;
    } on ReportLoadCancelled {
      return;
    } catch (e) {
      if (_disposed || !identical(_ticket, ticket)) return;
      _error = e;
    }
    _ticket = null;
    _loading = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _ticket?.cancel();
    progress.dispose();
    super.dispose();
  }
}
