import 'dart:collection';

import 'package:flutter/foundation.dart';

/// Resultados recientes de reportes, en memoria, para no volver a pedirle al
/// backend lo mismo cada vez que se abre un reporte o se vuelve a un periodo.
///
///  * Menos de [freshFor]: se muestra tal cual, sin consultar.
///  * Hasta [maxAge]: se muestra al instante y se refresca en segundo plano.
///  * Más viejo: no sirve, se carga de cero.
///
/// La clave lleva el negocio y el rango ([reportCacheKey]), así cambiar de
/// negocio nunca muestra datos de otro. Se vacía al cerrar sesión.
class ReportResultCache {
  ReportResultCache._();

  static const freshFor = Duration(seconds: 45);
  static const maxAge = Duration(minutes: 5);
  static const _maxEntries = 24;

  /// Inyectable en tests.
  @visibleForTesting
  static DateTime Function() now = DateTime.now;

  static final LinkedHashMap<String, _Entry> _entries = LinkedHashMap();

  static CachedReport<T>? read<T>(String key) {
    final entry = _entries.remove(key);
    if (entry == null) return null;
    final age = now().difference(entry.savedAt);
    if (age > maxAge || entry.value is! T) return null;
    _entries[key] = entry; // al final: el más usado sale de último
    return CachedReport(entry.value as T, isFresh: age <= freshFor);
  }

  static void write(String key, Object? value) {
    _entries.remove(key);
    _entries[key] = _Entry(value, now());
    while (_entries.length > _maxEntries) {
      _entries.remove(_entries.keys.first);
    }
  }

  static void clear() => _entries.clear();
}

class CachedReport<T> {
  const CachedReport(this.value, {required this.isFresh});

  final T value;

  /// Reciente: no hace falta refrescar.
  final bool isFresh;
}

class _Entry {
  const _Entry(this.value, this.savedAt);

  final Object? value;
  final DateTime savedAt;
}

/// Clave de caché de un reporte: nombre + negocio + rango + lo que cambie el
/// resultado (hora de corte, granularidad...).
String reportCacheKey(
  String report,
  String businessId,
  DateTime start,
  DateTime end, [
  List<Object?> extra = const [],
]) =>
    [
      report,
      businessId,
      start.toUtc().toIso8601String(),
      end.toUtc().toIso8601String(),
      ...extra,
    ].join('|');
