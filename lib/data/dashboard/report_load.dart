import 'dart:async';
import 'dart:collection';

/// Carga de reportes en segundo plano sin sobrecargar el backend.
///
/// Tres piezas que trabajan juntas:
///  * [ReportLoadTicket]: identifica UNA carga de reporte. Lleva el progreso
///    (peticiones y filas) y se puede cancelar: si el usuario cambia de periodo
///    o sale de la pantalla, la carga deja de pedir páginas.
///  * [ReportRequestThrottle]: tope global de peticiones en vuelo. Las de un
///    reporte van como "segundo plano" y ceden el paso a las del dashboard.
///  * [fetchAllPages] / [fetchInBatches]: paginación y lotes `inFilter` que
///    pasan por el tope y reportan al ticket.
///
/// El ticket viaja en la [Zone] de la carga ([ReportLoadTicket.run]), así los
/// servicios no tienen que pasarlo de método en método: cualquier petición
/// hecha dentro de la carga lo encuentra en [ReportLoadTicket.current].

/// La carga se canceló (otro periodo, pantalla cerrada). No es un error: el
/// controlador lo descarta en silencio.
class ReportLoadCancelled implements Exception {
  const ReportLoadCancelled();

  @override
  String toString() => 'ReportLoadCancelled';
}

/// Avance de una carga. El total no se conoce de antemano (pedirlo costaría
/// un `count` extra por consulta), así que se cuenta lo hecho.
class ReportLoadProgress {
  const ReportLoadProgress({this.requests = 0, this.rows = 0});

  static const none = ReportLoadProgress();

  /// Peticiones terminadas (páginas, lotes y consultas sueltas).
  final int requests;

  /// Filas recibidas hasta ahora.
  final int rows;
}

class ReportLoadTicket {
  ReportLoadTicket({this.onProgress});

  static final Object _zoneKey = Object();

  /// El ticket de la carga en curso, o null fuera de una carga de reporte.
  static ReportLoadTicket? get current =>
      Zone.current[_zoneKey] as ReportLoadTicket?;

  final void Function(ReportLoadProgress progress)? onProgress;

  bool _cancelled = false;
  int _requests = 0;
  int _rows = 0;

  bool get isCancelled => _cancelled;

  ReportLoadProgress get progress =>
      ReportLoadProgress(requests: _requests, rows: _rows);

  void cancel() => _cancelled = true;

  void throwIfCancelled() {
    if (_cancelled) throw const ReportLoadCancelled();
  }

  /// Corre [body] con este ticket como [current].
  Future<T> run<T>(Future<T> Function() body) =>
      runZoned(body, zoneValues: {_zoneKey: this});

  void _record(Object? result) {
    if (_cancelled) return;
    _requests += 1;
    if (result is List) _rows += result.length;
    onProgress?.call(progress);
  }
}

/// Tope global de peticiones en vuelo hacia Supabase.
///
/// Las peticiones hechas dentro de un [ReportLoadTicket] son de segundo plano:
/// ocupan como mucho [maxBackgroundInFlight] cupos y siempre esperan detrás de
/// las demás. Así un reporte de un mes entero (decenas de lotes) nunca deja al
/// dashboard sin cupo ni dispara decenas de peticiones simultáneas.
class ReportRequestThrottle {
  ReportRequestThrottle._();

  static const maxInFlight = 4;
  static const maxBackgroundInFlight = 3;

  static int _active = 0;
  static int _activeBackground = 0;
  static final Queue<Completer<void>> _foreground = Queue();
  static final Queue<Completer<void>> _background = Queue();

  /// Corre [request] cuando haya cupo. Si la carga se canceló mientras
  /// esperaba, no la manda.
  static Future<T> run<T>(Future<T> Function() request) async {
    final ticket = ReportLoadTicket.current;
    final background = ticket != null;
    ticket?.throwIfCancelled();
    await _acquire(background);
    try {
      ticket?.throwIfCancelled();
      final result = await request();
      ticket?._record(result);
      return result;
    } finally {
      _release(background);
    }
  }

  static bool _hasRoom(bool background) =>
      _active < maxInFlight &&
      (!background || _activeBackground < maxBackgroundInFlight);

  static Future<void> _acquire(bool background) {
    final queueFree = background
        ? _foreground.isEmpty && _background.isEmpty
        : _foreground.isEmpty;
    if (queueFree && _hasRoom(background)) {
      _take(background);
      return Future.value();
    }
    final waiter = Completer<void>();
    (background ? _background : _foreground).add(waiter);
    return waiter.future;
  }

  static void _take(bool background) {
    _active += 1;
    if (background) _activeBackground += 1;
  }

  static void _release(bool background) {
    _active -= 1;
    if (background) _activeBackground -= 1;
    // Primero las del dashboard; las de reporte solo si no hay ninguna
    // esperando (aunque haya cupo de segundo plano).
    while (true) {
      if (_foreground.isNotEmpty) {
        if (!_hasRoom(false)) return;
        _take(false);
        _foreground.removeFirst().complete();
        continue;
      }
      if (_background.isNotEmpty && _hasRoom(true)) {
        _take(true);
        _background.removeFirst().complete();
        continue;
      }
      return;
    }
  }
}

/// Trae todas las páginas de una consulta PostgREST (que corta en ~1000
/// filas) avanzando con `.range()` hasta una página corta. Una página a la
/// vez, cada una por [ReportRequestThrottle].
Future<List<Map<String, dynamic>>> fetchAllPages(
  Future<dynamic> Function(int from, int to) page, {
  int pageSize = 1000,
}) async {
  final all = <Map<String, dynamic>>[];
  var from = 0;
  while (true) {
    final res = await ReportRequestThrottle.run(
      () => page(from, from + pageSize - 1),
    );
    final list = List<Map<String, dynamic>>.from(res as List);
    all.addAll(list);
    if (list.length < pageSize) break;
    from += pageSize;
  }
  return all;
}

/// Corre [query] por lotes de [values] (un `inFilter` largo revienta el
/// límite de la URI). Los lotes se encolan en [ReportRequestThrottle]: nunca
/// salen todos a la vez.
Future<List<Map<String, dynamic>>> fetchInBatches(
  List<String> values,
  Future<dynamic> Function(List<String> chunk) query, {
  int batchSize = 40,
}) async {
  if (values.isEmpty) return [];
  final futures = <Future<dynamic>>[
    for (var i = 0; i < values.length; i += batchSize)
      ReportRequestThrottle.run(
        () => query(values.sublist(
          i,
          i + batchSize > values.length ? values.length : i + batchSize,
        )),
      ),
  ];
  final batches = await Future.wait(futures);
  return [
    for (final batch in batches) ...List<Map<String, dynamic>>.from(batch as List),
  ];
}
