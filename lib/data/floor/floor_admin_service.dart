import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/floor/floor_models.dart';

/// Zonas y mesas del salón contra el Supabase compartido con el POS. Escribe
/// las mismas tablas y columnas que la pantalla "Zonas y mesas" del POS
/// (zones_tables_viewmodel), gated por la misma RLS.
///
/// Diferencia a propósito: el POS intenta el DELETE y solo desactiva si una
/// FK lo frena; pero `table_sessions.table_id` y `orders.session_id` son
/// ON DELETE CASCADE, así que una mesa cuyo historial no tenga pagos ni NCF
/// se borraría con sus sesiones, órdenes y productos. Aquí, si hay historial,
/// se desactiva sin intentar borrar.
class FloorAdminService {
  FloorAdminService(this._client);

  final SupabaseClient _client;

  /// Zonas (activas e inactivas, sin las virtuales de venta manual/rápida)
  /// con sus mesas.
  Future<({List<FloorZone> zones, List<FloorTable> tables})> loadFloor(
    String businessId,
  ) {
    return _guard(() async {
      final zoneRows = await _client
          .from('zones')
          .select('id, name, sort_index, is_active')
          .eq('business_id', businessId)
          .order('sort_index')
          .order('name');
      final zones = List<Map<String, dynamic>>.from(zoneRows)
          .map(FloorZone.fromJson)
          .where((z) => !isVirtualSalesZone(z))
          .toList(growable: false);
      if (zones.isEmpty) {
        return (zones: zones, tables: const <FloorTable>[]);
      }
      final tableRows = await _client
          .from('dining_tables')
          .select('id, zone_id, code, label, capacity, is_active, state')
          .inFilter('zone_id', [for (final z in zones) z.id]);
      final tables = List<Map<String, dynamic>>.from(
        tableRows,
      ).map(FloorTable.fromJson).toList(growable: false);
      return (zones: zones, tables: tables);
    });
  }

  /// Las zonas que el POS crea solo para venta manual / rápida (sort_index
  /// 900/901 con ese nombre). Misma regla que `ZonesRepository` del POS.
  static bool isVirtualSalesZone(FloorZone zone) {
    if (zone.sortIndex != 900 && zone.sortIndex != 901) return false;
    final name = zone.name
        .trim()
        .toLowerCase()
        .replaceAll('á', 'a')
        .replaceAll('é', 'e')
        .replaceAll('í', 'i')
        .replaceAll('ó', 'o')
        .replaceAll('ú', 'u')
        .replaceAll(RegExp(r'\s+'), ' ');
    return name == 'ventas manuales' || name == 'ventas rapidas';
  }

  // ── Zonas ──

  Future<void> createZone({
    required String businessId,
    required String name,
    required int sortIndex,
  }) {
    return _guard(
      () => _client.from('zones').insert({
        'business_id': businessId,
        'name': name,
        'sort_index': sortIndex,
      }),
    );
  }

  Future<void> renameZone(String zoneId, String name) {
    return _guard(
      () => _client.from('zones').update({'name': name}).eq('id', zoneId),
    );
  }

  /// Guarda el orden en `sort_index` (pasos de 10, como el POS; nunca llega
  /// a 900/901). Solo escribe las que cambiaron.
  Future<void> reorderZones(List<FloorZone> ordered) {
    return _guard(() async {
      for (var i = 0; i < ordered.length; i++) {
        final newIdx = (i + 1) * 10;
        if (ordered[i].sortIndex == newIdx) continue;
        await _client
            .from('zones')
            .update({'sort_index': newIdx})
            .eq('id', ordered[i].id);
      }
    });
  }

  /// Elimina una zona. Bloquea si tiene cuentas abiertas; si alguna de sus
  /// mesas tiene historial, desactiva la zona y sus mesas en vez de borrar.
  Future<FloorDeleteOutcome> deleteZone(String zoneId) {
    return _guard(() async {
      final open = await _client
          .from('table_sessions')
          .select('id, dining_tables!inner(zone_id)')
          .eq('dining_tables.zone_id', zoneId)
          .isFilter('closed_at', null)
          .limit(1);
      if ((open as List).isNotEmpty) {
        throw const FloorException(
          'No se puede eliminar la zona: tiene mesas con cuentas abiertas. Ciérralas primero.',
        );
      }
      final history = await _client
          .from('table_sessions')
          .select('id, dining_tables!inner(zone_id)')
          .eq('dining_tables.zone_id', zoneId)
          .limit(1);
      if ((history as List).isNotEmpty) {
        await _client
            .from('dining_tables')
            .update({'is_active': false})
            .eq('zone_id', zoneId);
        await _client
            .from('zones')
            .update({'is_active': false})
            .eq('id', zoneId);
        return FloorDeleteOutcome.deactivated;
      }
      // Sin historial: el CASCADE solo se lleva mesas que nunca se usaron.
      await _client.from('zones').delete().eq('id', zoneId);
      return FloorDeleteOutcome.deleted;
    });
  }

  /// Reactiva la zona y sus mesas.
  Future<void> reactivateZone(String zoneId) {
    return _guard(() async {
      await _client.from('zones').update({'is_active': true}).eq('id', zoneId);
      await _client
          .from('dining_tables')
          .update({'is_active': true})
          .eq('zone_id', zoneId);
    });
  }

  // ── Mesas ──

  /// Crea una mesa. Igual que el POS: sin nombre, el nombre es el código.
  Future<void> createTable({
    required String zoneId,
    required String code,
    String? label,
    required int capacity,
  }) {
    return _guard(
      () => _client.from('dining_tables').insert({
        'zone_id': zoneId,
        'code': code,
        'label': (label == null || label.isEmpty) ? code : label,
        'capacity': capacity,
      }),
    );
  }

  /// Crea varias mesas de una vez, saltando los códigos que ya existen en la
  /// zona ([existingCodes], en minúsculas).
  Future<({int created, int skipped})> createTablesBulk({
    required String zoneId,
    required List<String> codes,
    required int capacity,
    required Set<String> existingCodes,
  }) {
    return _guard(() async {
      final rows = <Map<String, dynamic>>[];
      var skipped = 0;
      for (final code in codes) {
        if (existingCodes.contains(code.toLowerCase())) {
          skipped++;
          continue;
        }
        rows.add({
          'zone_id': zoneId,
          'code': code,
          'label': code,
          'capacity': capacity,
        });
      }
      if (rows.isNotEmpty) {
        await _client.from('dining_tables').insert(rows);
      }
      return (created: rows.length, skipped: skipped);
    });
  }

  Future<void> updateTable({
    required String tableId,
    required String code,
    String? label,
    required int capacity,
  }) {
    return _guard(
      () => _client
          .from('dining_tables')
          .update({
            'code': code,
            'label': (label == null || label.isEmpty) ? code : label,
            'capacity': capacity,
          })
          .eq('id', tableId),
    );
  }

  /// Cambia la mesa de zona sin tocar sus cuentas (RPC del POS, valida que el
  /// usuario sea admin y que ambas zonas sean del mismo negocio).
  Future<void> moveTable({
    required String tableId,
    required String targetZoneId,
  }) {
    return _guard(
      () => _client.rpc(
        'fn_move_table_to_zone',
        params: {'p_table_id': tableId, 'p_target_zone_id': targetZoneId},
      ),
    );
  }

  /// Elimina una mesa. Bloquea si no está libre o tiene cuenta abierta; si
  /// tiene historial, la desactiva en vez de borrarla.
  Future<FloorDeleteOutcome> deleteTable(String tableId) {
    return _guard(() async {
      final row = await _client
          .from('dining_tables')
          .select('id, zone_id, code, label, capacity, is_active, state')
          .eq('id', tableId)
          .maybeSingle();
      if (row == null) {
        throw const FloorException('La mesa ya no existe.');
      }
      final table = FloorTable.fromJson(row);
      final stateLabel = table.stateLabel;
      if (stateLabel != null) {
        throw FloorException(
          'No se puede eliminar ${table.displayName}: está ${stateLabel.toLowerCase()}. Libérala primero.',
        );
      }
      final open = await _client
          .from('table_sessions')
          .select('id')
          .eq('table_id', tableId)
          .isFilter('closed_at', null)
          .limit(1);
      if ((open as List).isNotEmpty) {
        throw FloorException(
          'No se puede eliminar ${table.displayName}: tiene una cuenta abierta.',
        );
      }
      final history = await _client
          .from('table_sessions')
          .select('id')
          .eq('table_id', tableId)
          .limit(1);
      if ((history as List).isNotEmpty) {
        await _client
            .from('dining_tables')
            .update({'is_active': false})
            .eq('id', tableId);
        return FloorDeleteOutcome.deactivated;
      }
      await _client.from('dining_tables').delete().eq('id', tableId);
      return FloorDeleteOutcome.deleted;
    });
  }

  Future<void> reactivateTable(String tableId) {
    return _guard(
      () => _client
          .from('dining_tables')
          .update({'is_active': true})
          .eq('id', tableId),
    );
  }

  /// Traduce los errores de la base a mensajes para el usuario.
  Future<T> _guard<T>(Future<T> Function() op) async {
    try {
      return await op();
    } on FloorException {
      rethrow;
    } on PostgrestException catch (e) {
      throw FloorException.fromPostgrest(e);
    }
  }
}

/// Error del módulo de salón, con mensaje apto para mostrar.
class FloorException implements Exception {
  const FloorException(this.message);

  factory FloorException.fromPostgrest(PostgrestException e) {
    final raw = e.message;
    if (raw.contains('NOT_AUTHORIZED')) {
      return const FloorException(
        'Solo un administrador puede mover mesas entre zonas.',
      );
    }
    if (raw.contains('TARGET_ZONE_NOT_FOUND') ||
        raw.contains('TABLE_NOT_FOUND')) {
      return const FloorException(
        'La mesa o la zona ya no existe. Actualiza la pantalla.',
      );
    }
    switch (e.code) {
      case '23505':
        return const FloorException(
          'Ya existe una mesa con ese código en la zona (puede estar desactivada).',
        );
      case '23503':
        return const FloorException(
          'No se puede eliminar: tiene historial de ventas.',
        );
      case '23514':
        return const FloorException('Un valor está fuera de rango.');
      case '42501':
        return const FloorException('No tienes permiso para esta operación.');
    }
    return FloorException(raw);
  }

  final String message;

  @override
  String toString() => message;
}
