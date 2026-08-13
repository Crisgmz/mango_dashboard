import 'package:flutter/foundation.dart';

/// A warehouse / bodega within a business.
@immutable
class WarehouseInfo {
  const WarehouseInfo({
    required this.id,
    required this.name,
    this.isMain = false,
  });

  final String id;
  final String name;
  final bool isMain;
}

/// A single inventory item (insumo / ingredient / raw material) with its
/// current stock rolled up across all warehouses + optional per-warehouse
/// breakdown for the drill-down.
@immutable
class InventoryItemSnapshot {
  const InventoryItemSnapshot({
    required this.itemId,
    required this.name,
    required this.unit,
    required this.totalQuantity,
    this.sku,
    this.cost,
    this.minStock = 0,
    this.maxStock,
    this.byWarehouse = const [],
  });

  final String itemId;
  final String name;
  final String? sku;
  final String unit;
  final double? cost;
  final double minStock;
  final double? maxStock;
  final double totalQuantity;
  final List<WarehouseStock> byWarehouse;

  /// `low` when current stock is at or below the configured minimum
  /// (but minimum must be > 0 to be meaningful — items without min set
  /// are never "low").
  bool get isLow => minStock > 0 && totalQuantity <= minStock;

  bool get isOut => totalQuantity <= 0;

  /// Suggested quantity to purchase to refill to `maxStock` (when set),
  /// otherwise to bring stock to `2 × minStock` as a sensible default.
  double get suggestedPurchase {
    if (maxStock != null && maxStock! > totalQuantity) {
      return maxStock! - totalQuantity;
    }
    if (minStock > 0 && totalQuantity < minStock) {
      return (minStock * 2) - totalQuantity;
    }
    return 0;
  }
}

/// Movimiento del kardex (vista `v_inventory_movements_with_balance`):
/// tipo, delta firmado, saldo corrido y quién lo hizo. Solo lectura.
@immutable
class KardexEntry {
  const KardexEntry({
    required this.id,
    required this.movementType,
    required this.quantity,
    required this.runningBalance,
    this.warehouseName,
    this.reasonCode,
    this.referenceType,
    this.notes,
    this.createdByName,
    this.createdAt,
  });

  final String id;
  final String movementType;

  /// Delta firmado (+entrada / −salida).
  final double quantity;

  /// Saldo resultante en la bodega tras este movimiento.
  final double runningBalance;
  final String? warehouseName;
  final String? reasonCode;
  final String? referenceType;
  final String? notes;
  final String? createdByName;
  final DateTime? createdAt;

  String get typeLabel {
    switch (movementType) {
      case 'purchase':
        return 'Compra';
      case 'sale':
        return 'Venta';
      case 'adjustment':
        return 'Ajuste';
      case 'transfer_in':
        return 'Transf. entrada';
      case 'transfer_out':
        return 'Transf. salida';
      case 'waste':
        return 'Merma';
      case 'return':
        return 'Devolución';
      default:
        return movementType;
    }
  }

  factory KardexEntry.fromJson(Map<String, dynamic> json) {
    double toD(dynamic v) =>
        v is num ? v.toDouble() : double.tryParse(v?.toString() ?? '') ?? 0;
    return KardexEntry(
      id: json['id']?.toString() ?? '',
      movementType: json['movement_type']?.toString() ?? '',
      quantity: toD(json['quantity']),
      runningBalance: toD(json['running_balance']),
      warehouseName: json['warehouse_name']?.toString(),
      reasonCode: json['reason_code']?.toString(),
      referenceType: json['reference_type']?.toString(),
      notes: json['notes']?.toString(),
      createdByName: json['created_by_name']?.toString(),
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? ''),
    );
  }
}

@immutable
class WarehouseStock {
  const WarehouseStock({
    required this.warehouseId,
    required this.warehouseName,
    required this.quantity,
  });

  final String warehouseId;
  final String warehouseName;
  final double quantity;
}
