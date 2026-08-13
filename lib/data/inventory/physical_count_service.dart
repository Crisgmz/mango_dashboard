import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/inventory/physical_count_models.dart';

/// Conteos físicos (PRD 6.1 F5) contra las RPCs existentes del backend
/// (`fn_physical_count_*`, migraciones 20260516_0011 + 20260801_0002):
/// crear (con modo ciego), congelar snapshot, contar por ítem, pedir
/// reconteo, completar (genera ajustes solo de lo contado) y cancelar.
class PhysicalCountService {
  PhysicalCountService(this._client);

  final SupabaseClient _client;

  Future<List<CountSession>> loadSessions(String businessId) async {
    final rows = await _client
        .from('physical_count_sessions')
        .select(
            'id, code, status, warehouse_id, is_blind, notes, started_at, completed_at, warehouses(name)')
        .eq('business_id', businessId)
        .order('started_at', ascending: false)
        .limit(100);
    return List<Map<String, dynamic>>.from(rows)
        .map(CountSession.fromJson)
        .toList(growable: false);
  }

  Future<CountSession> loadSession(String sessionId) async {
    final row = await _client
        .from('physical_count_sessions')
        .select(
            'id, code, status, warehouse_id, is_blind, notes, started_at, completed_at, warehouses(name)')
        .eq('id', sessionId)
        .single();
    return CountSession.fromJson(Map<String, dynamic>.from(row));
  }

  Future<List<CountLine>> loadLines(String sessionId) async {
    final rows = await _client
        .from('physical_count_lines')
        .select(
            'id, item_id, snapshot_quantity, counted_quantity, counter_notes, recount_requested, inventory_items(name, unit, cost)')
        .eq('session_id', sessionId)
        .order('created_at', ascending: true);
    return List<Map<String, dynamic>>.from(rows)
        .map(CountLine.fromJson)
        .toList(growable: false);
  }

  /// Crea la sesión (draft). [isBlind] oculta el snapshot al contador.
  Future<String> createSession({
    required String businessId,
    required String warehouseId,
    String? notes,
    bool isBlind = false,
  }) async {
    final result = await _client.rpc('fn_physical_count_create', params: {
      'p_business_id': businessId,
      'p_warehouse_id': warehouseId,
      'p_notes': notes,
      'p_is_blind': isBlind,
    });
    final map = result is Map ? Map<String, dynamic>.from(result) : const {};
    final id = map['session_id']?.toString() ?? map['id']?.toString();
    if (id == null || id.isEmpty) {
      throw Exception('No se pudo crear el conteo.');
    }
    return id;
  }

  /// Congela el stock actual como snapshot y pasa a in_progress.
  Future<void> freeze(String sessionId) async {
    await _client
        .rpc('fn_physical_count_freeze', params: {'p_session_id': sessionId});
  }

  Future<void> setCount({
    required String sessionId,
    required String itemId,
    required double countedQuantity,
    String? notes,
  }) async {
    await _client.rpc('fn_physical_count_set_count', params: {
      'p_session_id': sessionId,
      'p_item_id': itemId,
      'p_counted_quantity': countedQuantity,
      'p_notes': notes,
    });
  }

  Future<void> requestRecount({
    required String sessionId,
    required List<String> itemIds,
  }) async {
    await _client.rpc('fn_physical_count_request_recount', params: {
      'p_session_id': sessionId,
      'p_item_ids': itemIds,
    });
  }

  /// Completa el conteo: genera ajustes SOLO para las líneas contadas
  /// (las no contadas mantienen su stock — semántica de conteo cíclico).
  Future<Map<String, dynamic>> complete(String sessionId) async {
    final result = await _client
        .rpc('fn_physical_count_complete', params: {'p_session_id': sessionId});
    return result is Map
        ? Map<String, dynamic>.from(result)
        : <String, dynamic>{};
  }

  Future<void> cancel(String sessionId, {String? reason}) async {
    await _client.rpc('fn_physical_count_cancel', params: {
      'p_session_id': sessionId,
      'p_reason': reason,
    });
  }
}
