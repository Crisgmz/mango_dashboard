import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/inventory/stock_transfer_models.dart';

/// Transferencias entre bodegas contra las RPCs existentes del backend
/// (`fn_inventory_transfer_send/approve/receive/cancel`, migraciones
/// 20260513_0018 + 20260516_0009): envío atómico vía bodega __IN_TRANSIT__,
/// aprobación opcional según settings del negocio, y recepción con faltante
/// auditado.
class StockTransferService {
  StockTransferService(this._client);

  final SupabaseClient _client;

  Future<List<StockTransfer>> loadTransfers(String businessId) async {
    final rows = await _client
        .from('v_inventory_transfers_log')
        .select(
            'transfer_id, transfer_number, status, from_warehouse_name, '
            'to_warehouse_name, is_cross_business, to_business_name, '
            'created_by_name, item_count, total_sent, total_received, '
            'sent_at, received_at, notes')
        .eq('business_id', businessId)
        .order('sent_at', ascending: false)
        .limit(100);
    return List<Map<String, dynamic>>.from(rows)
        .map(StockTransfer.fromJson)
        .toList(growable: false);
  }

  Future<List<StockTransferItem>> loadItems(String transferId) async {
    final rows = await _client
        .from('stock_transfer_items')
        .select(
            'id, item_id, quantity_sent, quantity_received, variance_reason, '
            'inventory_items!stock_transfer_items_item_id_fkey(name, unit)')
        .eq('stock_transfer_id', transferId);
    return List<Map<String, dynamic>>.from(rows)
        .map(StockTransferItem.fromJson)
        .toList(growable: false);
  }

  /// Crea y envía la transferencia (o la deja pendiente de aprobación si el
  /// negocio lo exige). [items]: `[{item_id, quantity}]`.
  Future<void> send({
    required String businessId,
    required String fromWarehouseId,
    required String toWarehouseId,
    required List<Map<String, dynamic>> items,
    String? notes,
  }) async {
    await _client.rpc('fn_inventory_transfer_send', params: {
      'p_business_id': businessId,
      'p_from_warehouse_id': fromWarehouseId,
      'p_to_warehouse_id': toWarehouseId,
      'p_items': items,
      'p_notes': notes,
    });
  }

  Future<void> approve(String transferId) async {
    await _client.rpc('fn_inventory_transfer_approve',
        params: {'p_transfer_id': transferId});
  }

  /// Recibe en destino. [receivedItems]: `[{transfer_item_id,
  /// quantity_received}]`. Un faltante queda como ajuste en tránsito.
  Future<void> receive({
    required String transferId,
    required List<Map<String, dynamic>> receivedItems,
    String? varianceNotes,
  }) async {
    await _client.rpc('fn_inventory_transfer_receive', params: {
      'p_transfer_id': transferId,
      'p_received_items': receivedItems,
      'p_variance_notes': varianceNotes,
    });
  }

  Future<void> cancel(String transferId, {String? reason}) async {
    await _client.rpc('fn_inventory_transfer_cancel', params: {
      'p_transfer_id': transferId,
      'p_reason': reason,
    });
  }
}
