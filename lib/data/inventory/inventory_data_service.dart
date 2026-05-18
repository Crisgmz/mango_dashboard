import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/inventory/inventory_models.dart';

/// Loads inventory snapshots for the admin dashboard.
///
/// Sourced from three tables: `inventory_items` (the master), `inventory_stock`
/// (qty per warehouse), and `warehouses` (so we can label rows). Stock is
/// rolled up across warehouses for the headline number and broken down per
/// warehouse for the drill-down.
class InventoryDataService {
  InventoryDataService(this._client);

  final SupabaseClient _client;

  /// Loads all active inventory items for [businessId] with their current
  /// stock from every active warehouse. Items without any stock row are
  /// included with `totalQuantity = 0` (so newly created items still show).
  Future<List<InventoryItemSnapshot>> loadInventory(String businessId) async {
    // Two parallel reads — items master + warehouses + stock rows.
    final results = await Future.wait([
      _client
          .from('inventory_items')
          .select('id, sku, name, unit, cost, min_stock, max_stock')
          .eq('business_id', businessId)
          .eq('is_active', true)
          .order('name', ascending: true),
      _client
          .from('warehouses')
          .select('id, name, is_main')
          .eq('business_id', businessId)
          .eq('is_active', true),
    ]);

    final itemRows = List<Map<String, dynamic>>.from(results[0]);
    final warehouseRows = List<Map<String, dynamic>>.from(results[1]);

    if (itemRows.isEmpty) return const [];

    final warehouseById = <String, WarehouseInfo>{
      for (final w in warehouseRows)
        if (w['id'] != null)
          w['id'].toString(): WarehouseInfo(
            id: w['id'].toString(),
            name: w['name']?.toString() ?? 'Bodega',
            isMain: w['is_main'] == true,
          ),
    };

    // Stock filtered to this business's warehouses.
    final warehouseIds = warehouseById.keys.toList(growable: false);
    final stockRows = warehouseIds.isEmpty
        ? const <Map<String, dynamic>>[]
        : List<Map<String, dynamic>>.from(await _client
            .from('inventory_stock')
            .select('warehouse_id, item_id, quantity')
            .inFilter('warehouse_id', warehouseIds));

    // Group stock rows by item.
    final stocksByItem = <String, List<WarehouseStock>>{};
    final totalsByItem = <String, double>{};
    for (final row in stockRows) {
      final itemId = row['item_id']?.toString();
      final whId = row['warehouse_id']?.toString();
      if (itemId == null || whId == null) continue;
      final qty = _toDouble(row['quantity']);
      final wh = warehouseById[whId];
      if (wh == null) continue;
      stocksByItem.putIfAbsent(itemId, () => []).add(WarehouseStock(
            warehouseId: whId,
            warehouseName: wh.name,
            quantity: qty,
          ));
      totalsByItem.update(itemId, (v) => v + qty, ifAbsent: () => qty);
    }

    return itemRows.map((row) {
      final id = row['id']?.toString() ?? '';
      final byWarehouse = stocksByItem[id] ?? const <WarehouseStock>[];
      // Stable ordering: main warehouse first, then alphabetical.
      final sorted = [...byWarehouse]..sort((a, b) {
          final aMain = warehouseById[a.warehouseId]?.isMain ?? false;
          final bMain = warehouseById[b.warehouseId]?.isMain ?? false;
          if (aMain != bMain) return aMain ? -1 : 1;
          return a.warehouseName.compareTo(b.warehouseName);
        });
      return InventoryItemSnapshot(
        itemId: id,
        name: row['name']?.toString() ?? 'Insumo',
        sku: row['sku']?.toString(),
        unit: row['unit']?.toString() ?? 'unidad',
        cost: _toDoubleOrNull(row['cost']),
        minStock: _toDouble(row['min_stock']),
        maxStock: _toDoubleOrNull(row['max_stock']),
        totalQuantity: totalsByItem[id] ?? 0,
        byWarehouse: sorted,
      );
    }).toList(growable: false);
  }

  /// Subscribes to changes on `inventory_stock` for the given warehouses
  /// and emits a void event whenever a change occurs. Caller should debounce
  /// (e.g. 500ms) and refetch via [loadInventory] to keep the UI fresh.
  RealtimeChannel subscribeStockChanges({
    required String channelTag,
    required void Function() onChange,
  }) {
    final channel = _client.channel('rt:inventory_stock:$channelTag');
    channel
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'inventory_stock',
          callback: (_) => onChange(),
        )
        .subscribe();
    return channel;
  }

  double _toDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }

  double? _toDoubleOrNull(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString());
  }
}
