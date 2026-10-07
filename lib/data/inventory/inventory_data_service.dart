import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/inventory/inventory_models.dart';
import '../../domain/inventory/metrics_models.dart';

/// Loads inventory snapshots for the admin dashboard.
///
/// Sourced from three tables: `inventory_items` (the master), `inventory_stock`
/// (qty per warehouse), and `warehouses` (so we can label rows). Stock is
/// rolled up across warehouses for the headline number and broken down per
/// warehouse for the drill-down.
class InventoryDataService {
  InventoryDataService(this._client);

  final SupabaseClient _client;

  /// Precio de venta del producto vinculado a cada insumo
  /// (`menu_items.inventory_item_id`, retail 1:1) — alimenta la columna
  /// Margen de la Vista de stock (PRD 6.2 B.1). Si varios productos apuntan
  /// al mismo insumo, gana el de mayor precio.
  Future<Map<String, double>> loadLinkedPrices(String businessId) async {
    final rows = await _client
        .from('menu_items')
        .select('inventory_item_id, price')
        .eq('business_id', businessId)
        .eq('is_inventory_tracked', true)
        .not('inventory_item_id', 'is', null);
    final byItem = <String, double>{};
    for (final row in List<Map<String, dynamic>>.from(rows)) {
      final itemId = row['inventory_item_id']?.toString();
      if (itemId == null) continue;
      final price = row['price'] is num
          ? (row['price'] as num).toDouble()
          : double.tryParse(row['price']?.toString() ?? '') ?? 0;
      if (price > (byItem[itemId] ?? 0)) byItem[itemId] = price;
    }
    return byItem;
  }

  /// Unidades comprometidas por insumo en órdenes ABIERTAS del POS (ítems
  /// vivos de productos con vínculo directo a inventario). Alimenta
  /// Disponible = En mano − comprometido (PRD 6.2 B.1). Solo cubre el vínculo
  /// directo retail; el consumo por receta queda fuera (PRD aparte).
  Future<Map<String, double>> loadCommittedByItem(String businessId) async {
    final rows = await _client
        .from('order_items')
        .select(
            'qty, menu_items!inner(inventory_item_id), orders!inner(closed_at, status_ext, table_sessions!inner(business_id))')
        .eq('orders.table_sessions.business_id', businessId)
        .isFilter('orders.closed_at', null)
        .neq('orders.status_ext', 'void')
        .not('status', 'in', '(void,paid)')
        .not('menu_items.inventory_item_id', 'is', null)
        .limit(2000);
    final byItem = <String, double>{};
    for (final row in List<Map<String, dynamic>>.from(rows)) {
      final mi = row['menu_items'];
      final itemId =
          mi is Map<String, dynamic> ? mi['inventory_item_id']?.toString() : null;
      if (itemId == null) continue;
      final qty = row['qty'] is num
          ? (row['qty'] as num).toDouble()
          : double.tryParse(row['qty']?.toString() ?? '') ?? 0;
      if (qty <= 0) continue;
      byItem[itemId] = (byItem[itemId] ?? 0) + qty;
    }
    return byItem;
  }

  /// Valoración con clase ABC (vista `v_inventory_valuation_summary`),
  /// ordenada por valor descendente.
  Future<List<ValuationItem>> loadValuationSummary(String businessId) async {
    final rows = await _client
        .from('v_inventory_valuation_summary')
        .select(
            'item_id, item_name, item_unit, total_quantity, total_value, '
            'cumulative_pct, abc_class, last_movement_at')
        .eq('business_id', businessId)
        .order('total_value', ascending: false)
        .limit(500);
    return List<Map<String, dynamic>>.from(rows)
        .map(ValuationItem.fromJson)
        .toList(growable: false);
  }

  /// Merma de los últimos [daysBack] días: salidas del kardex con motivo de
  /// pérdida (rotura/vencimiento/robo/donación) valoradas a costo. 'correction'
  /// y 'physical_count' NO cuentan como merma (son correcciones, no pérdidas).
  Future<List<WasteEntry>> loadWasteMovements(String businessId,
      {int daysBack = 30}) async {
    final since = DateTime.now()
        .subtract(Duration(days: daysBack))
        .toUtc()
        .toIso8601String();
    final rows = await _client
        .from('v_inventory_movements_with_balance')
        .select(
            'item_id, item_name, item_unit, quantity, total_value, '
            'reason_code, created_at')
        .eq('business_id', businessId)
        .inFilter(
            'reason_code', ['breakage', 'expiration', 'theft', 'donation'])
        .lt('quantity', 0)
        .gte('created_at', since)
        .order('created_at', ascending: false)
        .limit(2000);
    return List<Map<String, dynamic>>.from(rows)
        .map(WasteEntry.fromJson)
        .toList(growable: false);
  }

  /// Rotación por artículo en los últimos [daysBack] días
  /// (`fn_inventory_rotation_analysis`): velocidad de salida, días de
  /// cobertura y clase star/active/slow/dormant.
  Future<List<RotationItem>> loadRotationAnalysis(String businessId,
      {int daysBack = 30}) async {
    final rows = await _client.rpc('fn_inventory_rotation_analysis', params: {
      'p_business_id': businessId,
      'p_days_back': daysBack,
    });
    return List<Map<String, dynamic>>.from(rows as List)
        .map(RotationItem.fromJson)
        .toList(growable: false);
  }

  /// Campos extra de la ficha de artículo que el snapshot de lista no trae.
  Future<
      ({
        String? barcode,
        String? purchaseUnit,
        double packSize,
        String? preferredSupplierId,
        String? preferredSupplierName,
      })> loadItemExtras(String itemId) async {
    Map<String, dynamic> row;
    try {
      row = Map<String, dynamic>.from(await _client
          .from('inventory_items')
          .select(
              'barcode, purchase_unit, pack_size, preferred_supplier_id, suppliers(name)')
          .eq('id', itemId)
          .single());
    } on PostgrestException {
      // Backend sin la migración de suplidor preferido (20260813_0001).
      row = Map<String, dynamic>.from(await _client
          .from('inventory_items')
          .select('barcode, purchase_unit, pack_size')
          .eq('id', itemId)
          .single());
    }
    final rawPack = row['pack_size'];
    final supplier = row['suppliers'];
    return (
      barcode: row['barcode']?.toString(),
      purchaseUnit: row['purchase_unit']?.toString(),
      packSize: rawPack is num
          ? rawPack.toDouble()
          : double.tryParse(rawPack?.toString() ?? '') ?? 1,
      preferredSupplierId: row['preferred_supplier_id']?.toString(),
      preferredSupplierName: supplier is Map<String, dynamic>
          ? supplier['name']?.toString()
          : null,
    );
  }

  /// Suplidor preferido del insumo (manda sobre la heurística de última
  /// compra en "Qué comprar hoy"). Null lo limpia.
  Future<void> setPreferredSupplier(String itemId, String? supplierId) async {
    await _client
        .from('inventory_items')
        .update({'preferred_supplier_id': supplierId}).eq('id', itemId);
  }

  /// Kardex del artículo (vista `v_inventory_movements_with_balance`), del
  /// más reciente al más viejo.
  Future<List<KardexEntry>> loadKardex(String itemId, {int limit = 40}) async {
    final rows = await _client
        .from('v_inventory_movements_with_balance')
        .select(
            'id, movement_type, quantity, running_balance, warehouse_name, reason_code, reference_type, notes, created_by_name, created_at')
        .eq('item_id', itemId)
        .order('created_at', ascending: false)
        .limit(limit);
    return List<Map<String, dynamic>>.from(rows)
        .map(KardexEntry.fromJson)
        .toList(growable: false);
  }

  /// Consumo por venta de los últimos 28 días, para la cobertura
  /// (PRD 6.2 C.3): unidades vendidas por día.
  Future<double> loadDailySaleRate28d(String itemId) async {
    final since = DateTime.now()
        .subtract(const Duration(days: 28))
        .toUtc()
        .toIso8601String();
    final rows = await _client
        .from('inventory_movements')
        .select('quantity')
        .eq('item_id', itemId)
        .eq('movement_type', 'sale')
        .gte('created_at', since)
        .limit(5000);
    var total = 0.0;
    for (final row in List<Map<String, dynamic>>.from(rows)) {
      final q = row['quantity'];
      final v = q is num ? q.toDouble() : double.tryParse(q?.toString() ?? '') ?? 0;
      total += v.abs();
    }
    return total / 28;
  }

  /// Ajuste manual con motivo OBLIGATORIO vía `fn_inventory_adjust`: recibe la
  /// cantidad CONTADA (el delta lo calcula el servidor) y escribe el
  /// movimiento con reason_code — no hay edición silenciosa de cantidad.
  Future<void> adjustStock({
    required String businessId,
    required String warehouseId,
    required String itemId,
    required double countedQuantity,
    required String reasonCode,
    String? notes,
  }) async {
    await _client.rpc('fn_inventory_adjust', params: {
      'p_business_id': businessId,
      'p_warehouse_id': warehouseId,
      'p_item_id': itemId,
      'p_counted_quantity': countedQuantity,
      'p_reason_code': reasonCode,
      'p_notes': notes,
    });
  }

  /// Punto de reorden y stock máximo del artículo.
  Future<void> updateStockLimits({
    required String itemId,
    required double minStock,
    double? maxStock,
  }) async {
    await _client.from('inventory_items').update({
      'min_stock': minStock,
      'max_stock': maxStock,
    }).eq('id', itemId);
  }

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
