import 'package:flutter/foundation.dart';

/// Orden de compra (tabla `purchase_orders`). Estados del enum
/// `purchase_status` del backend: draft | sent | partial | received | cancelled.
@immutable
class PurchaseOrder {
  const PurchaseOrder({
    required this.id,
    required this.orderNumber,
    required this.status,
    required this.total,
    this.subtotal = 0,
    this.tax = 0,
    this.supplierId,
    this.supplierName,
    this.supplierWhatsapp,
    this.supplierPhone,
    this.warehouseId,
    this.expectedDate,
    this.receivedDate,
    this.createdAt,
    this.notes,
    this.lines = const [],
  });

  final String id;
  final String orderNumber;
  final String status;
  final double subtotal;
  final double tax;
  final double total;
  final String? supplierId;
  final String? supplierName;
  final String? supplierWhatsapp;
  final String? supplierPhone;
  final String? warehouseId;
  final DateTime? expectedDate;
  final DateTime? receivedDate;
  final DateTime? createdAt;
  final String? notes;
  final List<PurchaseOrderLine> lines;

  bool get isDraft => status == 'draft';
  bool get isOpen => status == 'draft' || status == 'sent' || status == 'partial';

  String get statusLabel {
    switch (status) {
      case 'draft':
        return 'Borrador';
      case 'sent':
        return 'Enviada';
      case 'partial':
        return 'Parcial';
      case 'received':
        return 'Recibida';
      case 'cancelled':
        return 'Cancelada';
      default:
        return status;
    }
  }

  factory PurchaseOrder.fromJson(Map<String, dynamic> json) {
    final supplier = json['suppliers'];
    return PurchaseOrder(
      id: json['id']?.toString() ?? '',
      orderNumber: json['order_number']?.toString() ?? '',
      status: json['status']?.toString() ?? 'draft',
      subtotal: _toDouble(json['subtotal']),
      tax: _toDouble(json['tax']),
      total: _toDouble(json['total']),
      supplierId: json['supplier_id']?.toString(),
      supplierName:
          supplier is Map<String, dynamic> ? supplier['name']?.toString() : null,
      supplierWhatsapp: supplier is Map<String, dynamic>
          ? supplier['whatsapp']?.toString()
          : null,
      supplierPhone:
          supplier is Map<String, dynamic> ? supplier['phone']?.toString() : null,
      warehouseId: json['warehouse_id']?.toString(),
      expectedDate: DateTime.tryParse(json['expected_date']?.toString() ?? ''),
      receivedDate: DateTime.tryParse(json['received_date']?.toString() ?? ''),
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? ''),
      notes: json['notes']?.toString(),
      lines: (json['purchase_order_items'] as List? ?? [])
          .whereType<Map<String, dynamic>>()
          .map(PurchaseOrderLine.fromJson)
          .toList(growable: false),
    );
  }

  static double _toDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }
}

/// Línea de una orden de compra (tabla `purchase_order_items`). Cantidades y
/// costos SIEMPRE en unidad base del insumo, igual que el POS y el ledger.
@immutable
class PurchaseOrderLine {
  const PurchaseOrderLine({
    required this.id,
    required this.description,
    required this.quantityOrdered,
    required this.unitCost,
    this.inventoryItemId,
    this.quantityReceived = 0,
    this.taxRate = 0,
    this.total = 0,
  });

  final String id;
  final String? inventoryItemId;
  final String description;
  final double quantityOrdered;
  final double quantityReceived;
  final double unitCost;
  final double taxRate;
  final double total;

  bool get fullyReceived => quantityReceived >= quantityOrdered;

  factory PurchaseOrderLine.fromJson(Map<String, dynamic> json) {
    return PurchaseOrderLine(
      id: json['id']?.toString() ?? '',
      inventoryItemId: json['inventory_item_id']?.toString(),
      description: json['description']?.toString() ?? 'Ítem',
      quantityOrdered: PurchaseOrder._toDouble(json['quantity_ordered']),
      quantityReceived: PurchaseOrder._toDouble(json['quantity_received']),
      unitCost: PurchaseOrder._toDouble(json['unit_cost']),
      taxRate: PurchaseOrder._toDouble(json['tax_rate']),
      total: PurchaseOrder._toDouble(json['total']),
    );
  }
}

/// Línea en edición dentro del formulario de nueva OC.
@immutable
class PurchaseOrderLineDraft {
  const PurchaseOrderLineDraft({
    required this.inventoryItemId,
    required this.description,
    required this.quantity,
    required this.unitCost,
    this.taxRate = 0,
    this.unit,
  });

  final String inventoryItemId;
  final String description;
  final double quantity;
  final double unitCost;

  /// Porcentaje 0-100 (el POS guarda `tax_rate` como %).
  final double taxRate;

  /// Unidad base del insumo, solo informativa en la UI.
  final String? unit;

  double get subtotal => quantity * unitCost;
  double get taxValue => subtotal * (taxRate / 100);
  double get total => subtotal;
}
