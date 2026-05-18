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
