import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/inventory/inventory_models.dart';
import '../../domain/purchasing/purchase_order.dart';
import '../../domain/purchasing/reorder_suggestion.dart';
import '../../domain/purchasing/supplier.dart';

/// Datos del módulo de compras (PRD 6.1) contra el Supabase compartido con el
/// POS. Mutaciones directas gated por RLS: `suppliers` escribe owner/admin
/// (política `sup_admin`); cualquier miembro lee.
class PurchasingDataService {
  PurchasingDataService(this._client);

  final SupabaseClient _client;

  // ── Suplidores ──

  Future<List<Supplier>> loadSuppliers(String businessId) async {
    final rows = await _client
        .from('suppliers')
        .select(
            'id, name, rnc, tax_id_type, contact_name, phone, whatsapp, email, '
            'address, payment_terms_days, notes, is_active')
        .eq('business_id', businessId)
        .order('name');
    return List<Map<String, dynamic>>.from(rows)
        .map(Supplier.fromJson)
        .toList(growable: false);
  }

  Future<void> createSupplier({
    required String businessId,
    required String name,
    String? rnc,
    String? taxIdType,
    String? contactName,
    String? phone,
    String? whatsapp,
    String? email,
    String? address,
    int paymentTermsDays = 0,
    String? notes,
  }) async {
    await _client.from('suppliers').insert(
      {
        'business_id': businessId,
        'name': name,
        'rnc': rnc,
        'tax_id_type': taxIdType,
        'contact_name': contactName,
        'phone': phone,
        'whatsapp': whatsapp,
        'email': email,
        'address': address,
        'payment_terms_days': paymentTermsDays,
        'notes': notes,
        'is_active': true,
      }..removeWhere((key, value) =>
          value == null || (value is String && value.isEmpty)),
    );
  }

  /// Edita un suplidor. Envía los campos explícitos (permite limpiar RNC,
  /// contacto, etc.).
  Future<void> updateSupplier({
    required String id,
    required String name,
    String? rnc,
    String? taxIdType,
    String? contactName,
    String? phone,
    String? whatsapp,
    String? email,
    String? address,
    int paymentTermsDays = 0,
    String? notes,
    required bool isActive,
  }) async {
    String? clean(String? v) => (v == null || v.trim().isEmpty) ? null : v.trim();
    await _client.from('suppliers').update({
      'name': name,
      'rnc': clean(rnc),
      'tax_id_type': clean(taxIdType),
      'contact_name': clean(contactName),
      'phone': clean(phone),
      'whatsapp': clean(whatsapp),
      'email': clean(email),
      'address': clean(address),
      'payment_terms_days': paymentTermsDays,
      'notes': clean(notes),
      'is_active': isActive,
    }).eq('id', id);
  }

  Future<void> setSupplierActive(String id, bool isActive) async {
    await _client.from('suppliers').update({'is_active': isActive}).eq('id', id);
  }

  /// Elimina un suplidor. Si una FK lo impide (tiene órdenes de compra o
  /// recepciones), lanza un error amable; el llamador ofrece desactivarlo.
  Future<void> deleteSupplier(String id) async {
    try {
      await _client.from('suppliers').delete().eq('id', id);
    } on PostgrestException catch (e) {
      if (e.code == '23503') {
        throw const PurchasingException(
          'No se puede eliminar: el suplidor tiene compras asociadas. Desactívalo en su lugar.',
        );
      }
      rethrow;
    }
  }

  // ── Órdenes de compra ──

  Future<List<PurchaseOrder>> loadPurchaseOrders(String businessId) async {
    final rows = await _client
        .from('purchase_orders')
        .select(
            'id, order_number, status, subtotal, tax, total, supplier_id, '
            'warehouse_id, expected_date, received_date, created_at, notes, '
            'suppliers(name, whatsapp, phone)')
        .eq('business_id', businessId)
        .order('created_at', ascending: false)
        .limit(300);
    return List<Map<String, dynamic>>.from(rows)
        .map(PurchaseOrder.fromJson)
        .toList(growable: false);
  }

  Future<PurchaseOrder> loadPurchaseOrderDetail(String orderId) async {
    final row = await _client
        .from('purchase_orders')
        .select(
            'id, order_number, status, subtotal, tax, total, supplier_id, '
            'warehouse_id, expected_date, received_date, created_at, notes, '
            'suppliers(name, whatsapp, phone), '
            'purchase_order_items(id, inventory_item_id, description, '
            'quantity_ordered, quantity_received, unit_cost, tax_rate, total)')
        .eq('id', orderId)
        .single();
    return PurchaseOrder.fromJson(Map<String, dynamic>.from(row));
  }

  Future<List<WarehouseInfo>> loadWarehouses(String businessId) async {
    final rows = await _client
        .from('warehouses')
        .select('id, name, is_main')
        .eq('business_id', businessId)
        .order('is_main', ascending: false)
        .order('name');
    return List<Map<String, dynamic>>.from(rows)
        .map((row) => WarehouseInfo(
              id: row['id']?.toString() ?? '',
              name: row['name']?.toString() ?? 'Bodega',
              isMain: row['is_main'] == true,
            ))
        .toList(growable: false);
  }

  /// Siguiente folio interno `PO-00001` — misma lógica que el POS
  /// (`purchases_repository.generateNextOrderNumber`).
  Future<String> generateNextOrderNumber(String businessId) async {
    final latest = await _client
        .from('purchase_orders')
        .select('order_number')
        .eq('business_id', businessId)
        .order('created_at', ascending: false)
        .limit(1)
        .maybeSingle();
    final raw = latest?['order_number']?.toString() ?? '';
    final match = RegExp(r'(\d+)$').firstMatch(raw);
    final next = match == null ? 1 : (int.tryParse(match.group(1)!) ?? 0) + 1;
    return 'PO-${next.toString().padLeft(5, '0')}';
  }

  /// Crea una OC con sus líneas. Espejo de
  /// `purchases_repository.createPurchaseOrder` del POS: totales calculados
  /// igual (subtotal + ITBIS por línea), cantidades y costos en unidad base.
  /// Devuelve el id de la orden creada.
  Future<String> createPurchaseOrder({
    required String businessId,
    required String supplierId,
    required String warehouseId,
    required String status, // 'draft' | 'sent'
    required DateTime expectedDate,
    String? notes,
    required List<PurchaseOrderLineDraft> lines,
  }) async {
    if (lines.isEmpty) {
      throw const PurchasingException('Agrega al menos una línea a la orden.');
    }
    final orderNumber = await generateNextOrderNumber(businessId);
    final subtotal = lines.fold<double>(0, (sum, l) => sum + l.total);
    final tax = lines.fold<double>(0, (sum, l) => sum + l.taxValue);
    final total = subtotal + tax;

    final created = await _client
        .from('purchase_orders')
        .insert({
          'business_id': businessId,
          'supplier_id': supplierId,
          'warehouse_id': warehouseId,
          'order_number': orderNumber,
          'status': status,
          'subtotal': subtotal,
          'tax': tax,
          'total': total,
          'expected_date': expectedDate.toIso8601String().split('T').first,
          'notes': notes,
        }..removeWhere((key, value) => value == null || value == ''))
        .select('id')
        .single();

    final orderId = created['id']?.toString();
    if (orderId == null || orderId.isEmpty) {
      throw const PurchasingException('No se pudo crear la orden de compra.');
    }

    await _client.from('purchase_order_items').insert([
      for (final l in lines)
        {
          'purchase_order_id': orderId,
          'inventory_item_id': l.inventoryItemId,
          'description': l.description,
          'quantity_ordered': l.quantity,
          'unit_cost': l.unitCost,
          'tax_rate': l.taxRate,
          'total': l.total,
        },
    ]);
    return orderId;
  }

  /// Marca una OC en borrador como enviada al suplidor.
  Future<void> markOrderSent(String orderId) async {
    await _client
        .from('purchase_orders')
        .update({'status': 'sent'})
        .eq('id', orderId)
        .eq('status', 'draft');
  }

  /// Cancela una OC abierta (draft/sent). Las parciales o recibidas no se
  /// cancelan desde aquí: ya movieron inventario.
  Future<void> cancelOrder(String orderId) async {
    await _client
        .from('purchase_orders')
        .update({'status': 'cancelled'})
        .eq('id', orderId)
        .inFilter('status', ['draft', 'sent']);
  }

  // ── Recepción (F3/F4) ──

  /// Umbral de variación de costo del negocio (%) para pintar el semáforo.
  Future<double> loadCostVarianceThreshold(String businessId) async {
    final row = await _client
        .from('business_settings')
        .select('cost_variance_threshold_pct')
        .eq('business_id', businessId)
        .maybeSingle();
    final raw = row?['cost_variance_threshold_pct'];
    if (raw is num) return raw.toDouble();
    return double.tryParse(raw?.toString() ?? '') ?? 3;
  }

  /// "On order" al estilo Square: cantidad pendiente por recibir por insumo,
  /// sumando las líneas de OCs enviadas o parciales del negocio.
  Future<Map<String, double>> loadOnOrderByItem(String businessId) async {
    final rows = await _client
        .from('purchase_order_items')
        .select(
            'inventory_item_id, quantity_ordered, quantity_received, purchase_orders!inner(business_id, status)')
        .eq('purchase_orders.business_id', businessId)
        .inFilter('purchase_orders.status', ['sent', 'partial']);
    final byItem = <String, double>{};
    for (final row in List<Map<String, dynamic>>.from(rows)) {
      final itemId = row['inventory_item_id']?.toString();
      if (itemId == null || itemId.isEmpty) continue;
      double toD(dynamic v) =>
          v is num ? v.toDouble() : double.tryParse(v?.toString() ?? '') ?? 0;
      final pending = toD(row['quantity_ordered']) - toD(row['quantity_received']);
      if (pending <= 0) continue;
      byItem[itemId] = (byItem[itemId] ?? 0) + pending;
    }
    return byItem;
  }

  /// "Qué comprar hoy": insumos en o bajo su punto de reorden, con cantidad
  /// sugerida y suplidor de la última compra
  /// (vista `v_inventory_reorder_suggestions`).
  Future<List<ReorderSuggestion>> loadReorderSuggestions(
      String businessId) async {
    final rows = await _client
        .from('v_inventory_reorder_suggestions')
        .select(
            'inventory_item_id, name, unit, sku, current_stock, min_stock, '
            'suggested_qty, cost, last_unit_cost, suggested_supplier_id, '
            'suggested_supplier_name')
        .eq('business_id', businessId)
        .order('deficit', ascending: false);
    return List<Map<String, dynamic>>.from(rows)
        .map(ReorderSuggestion.fromJson)
        .toList(growable: false);
  }

  /// "En orden" de UN artículo desglosado por bodega destino (ficha C.3).
  Future<Map<String, double>> loadItemOnOrderByWarehouse(
      String businessId, String itemId) async {
    final rows = await _client
        .from('purchase_order_items')
        .select(
            'quantity_ordered, quantity_received, purchase_orders!inner(business_id, warehouse_id, status)')
        .eq('inventory_item_id', itemId)
        .eq('purchase_orders.business_id', businessId)
        .inFilter('purchase_orders.status', ['sent', 'partial']);
    final byWarehouse = <String, double>{};
    for (final row in List<Map<String, dynamic>>.from(rows)) {
      final po = row['purchase_orders'];
      final wh =
          po is Map<String, dynamic> ? po['warehouse_id']?.toString() : null;
      if (wh == null) continue;
      double toD(dynamic v) =>
          v is num ? v.toDouble() : double.tryParse(v?.toString() ?? '') ?? 0;
      final pending = toD(row['quantity_ordered']) - toD(row['quantity_received']);
      if (pending <= 0) continue;
      byWarehouse[wh] = (byWarehouse[wh] ?? 0) + pending;
    }
    return byWarehouse;
  }

  /// Códigos de barra y SKU de los insumos indicados, para mapear el escaneo
  /// con cámara a líneas de la recepción. Devuelve código → item_id (el
  /// barcode manda; el sku entra como fallback si no colisiona).
  Future<Map<String, String>> loadItemCodes(List<String> itemIds) async {
    if (itemIds.isEmpty) return const {};
    final rows = await _client
        .from('inventory_items')
        .select('id, barcode, sku')
        .inFilter('id', itemIds);
    final byCode = <String, String>{};
    // Primero los SKU (menor prioridad), luego los barcode pisan.
    for (final row in List<Map<String, dynamic>>.from(rows)) {
      final id = row['id']?.toString();
      final sku = row['sku']?.toString().trim();
      if (id != null && sku != null && sku.isNotEmpty) byCode[sku] = id;
    }
    for (final row in List<Map<String, dynamic>>.from(rows)) {
      final id = row['id']?.toString();
      final barcode = row['barcode']?.toString().trim();
      if (id != null && barcode != null && barcode.isNotEmpty) {
        byCode[barcode] = id;
      }
    }
    return byCode;
  }

  /// Recibe mercancía vía `fn_receive_purchase_order_v2` (idempotente: la
  /// misma [idempotencyKey] nunca duplica; la RPC devuelve `replayed: true`).
  Future<Map<String, dynamic>> receivePurchaseOrder({
    required String warehouseId,
    required List<Map<String, dynamic>> lines,
    required String idempotencyKey,
    String? orderId,
    String? supplierId,
    Map<String, dynamic>? fiscal,
    String closeMode = 'complete',
    String? notes,
  }) async {
    final response = await _client.rpc('fn_receive_purchase_order_v2', params: {
      'p_warehouse_id': warehouseId,
      'p_lines': lines,
      'p_idempotency_key': idempotencyKey,
      'p_order_id': orderId,
      'p_supplier_id': supplierId,
      'p_fiscal': fiscal,
      'p_close_mode': closeMode,
      'p_notes': notes,
    });
    return response is Map
        ? Map<String, dynamic>.from(response)
        : <String, dynamic>{};
  }
}

/// Error de dominio del módulo de compras, con mensaje apto para mostrar.
class PurchasingException implements Exception {
  const PurchasingException(this.message);
  final String message;

  @override
  String toString() => message;
}
