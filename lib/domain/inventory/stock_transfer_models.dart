import 'package:flutter/foundation.dart';

/// Transferencia entre bodegas (vista `v_inventory_transfers_log`).
/// Flujo: pending_approval → sent → received | cancelled. El stock viaja por
/// la bodega virtual __IN_TRANSIT__; un faltante al recibir queda auditado
/// como ajuste en tránsito.
@immutable
class StockTransfer {
  const StockTransfer({
    required this.id,
    required this.number,
    required this.status,
    this.fromWarehouseName,
    this.toWarehouseName,
    this.isCrossBusiness = false,
    this.toBusinessName,
    this.createdByName,
    this.itemCount = 0,
    this.totalSent = 0,
    this.totalReceived = 0,
    this.sentAt,
    this.receivedAt,
    this.notes,
  });

  final String id;
  final String number;
  final String status;
  final String? fromWarehouseName;
  final String? toWarehouseName;
  final bool isCrossBusiness;
  final String? toBusinessName;
  final String? createdByName;
  final int itemCount;
  final double totalSent;
  final double totalReceived;
  final DateTime? sentAt;
  final DateTime? receivedAt;
  final String? notes;

  bool get isPendingApproval => status == 'pending_approval';
  bool get isInTransit => status == 'sent';

  String get statusLabel {
    switch (status) {
      case 'pending_approval':
        return 'Por aprobar';
      case 'sent':
        return 'En tránsito';
      case 'received':
        return 'Recibida';
      case 'cancelled':
        return 'Cancelada';
      default:
        return status;
    }
  }

  factory StockTransfer.fromJson(Map<String, dynamic> json) {
    double toD(dynamic v) =>
        v is num ? v.toDouble() : double.tryParse(v?.toString() ?? '') ?? 0;
    return StockTransfer(
      id: json['transfer_id']?.toString() ?? json['id']?.toString() ?? '',
      number: json['transfer_number']?.toString() ?? '',
      status: json['status']?.toString() ?? 'sent',
      fromWarehouseName: json['from_warehouse_name']?.toString(),
      toWarehouseName: json['to_warehouse_name']?.toString(),
      isCrossBusiness: json['is_cross_business'] == true,
      toBusinessName: json['to_business_name']?.toString(),
      createdByName: json['created_by_name']?.toString(),
      itemCount: json['item_count'] is int
          ? json['item_count'] as int
          : int.tryParse(json['item_count']?.toString() ?? '') ?? 0,
      totalSent: toD(json['total_sent']),
      totalReceived: toD(json['total_received']),
      sentAt: DateTime.tryParse(json['sent_at']?.toString() ?? ''),
      receivedAt: DateTime.tryParse(json['received_at']?.toString() ?? ''),
      notes: json['notes']?.toString(),
    );
  }
}

/// Línea de una transferencia (`stock_transfer_items`).
@immutable
class StockTransferItem {
  const StockTransferItem({
    required this.id,
    required this.itemId,
    required this.quantitySent,
    this.quantityReceived,
    this.itemName,
    this.unit,
    this.varianceReason,
  });

  final String id;
  final String itemId;
  final double quantitySent;
  final double? quantityReceived;
  final String? itemName;
  final String? unit;
  final String? varianceReason;

  double? get variance =>
      quantityReceived == null ? null : quantityReceived! - quantitySent;

  factory StockTransferItem.fromJson(Map<String, dynamic> json) {
    double toD(dynamic v) =>
        v is num ? v.toDouble() : double.tryParse(v?.toString() ?? '') ?? 0;
    final item = json['inventory_items'];
    return StockTransferItem(
      id: json['id']?.toString() ?? '',
      itemId: json['item_id']?.toString() ?? '',
      quantitySent: toD(json['quantity_sent']),
      quantityReceived: json['quantity_received'] == null
          ? null
          : toD(json['quantity_received']),
      itemName:
          item is Map<String, dynamic> ? item['name']?.toString() : null,
      unit: item is Map<String, dynamic> ? item['unit']?.toString() : null,
      varianceReason: json['variance_reason']?.toString(),
    );
  }
}
