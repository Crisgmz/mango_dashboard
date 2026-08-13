import 'package:flutter/foundation.dart';

/// Sugerencia de reorden (vista `v_inventory_reorder_suggestions`): insumo
/// en o bajo su punto de reorden, con cantidad sugerida (a max_stock o a 2×
/// el mínimo) y el suplidor de su última compra como heurística.
@immutable
class ReorderSuggestion {
  const ReorderSuggestion({
    required this.itemId,
    required this.name,
    required this.unit,
    required this.currentStock,
    required this.minStock,
    required this.suggestedQty,
    this.sku,
    this.cost = 0,
    this.lastUnitCost,
    this.supplierId,
    this.supplierName,
  });

  final String itemId;
  final String name;
  final String unit;
  final String? sku;
  final double currentStock;
  final double minStock;
  final double suggestedQty;

  /// Costo maestro (ponderado) del insumo.
  final double cost;

  /// Costo unitario de la última OC (mejor referencia para la nueva compra).
  final double? lastUnitCost;
  final String? supplierId;
  final String? supplierName;

  /// Costo a usar al armar la OC: el de la última compra, o el maestro.
  double get unitCost =>
      (lastUnitCost != null && lastUnitCost! > 0) ? lastUnitCost! : cost;

  double get estimatedTotal => suggestedQty * unitCost;

  factory ReorderSuggestion.fromJson(Map<String, dynamic> json) {
    double toD(dynamic v) =>
        v is num ? v.toDouble() : double.tryParse(v?.toString() ?? '') ?? 0;
    return ReorderSuggestion(
      itemId: json['inventory_item_id']?.toString() ?? '',
      name: json['name']?.toString() ?? 'Insumo',
      unit: json['unit']?.toString() ?? 'unidad',
      sku: json['sku']?.toString(),
      currentStock: toD(json['current_stock']),
      minStock: toD(json['min_stock']),
      suggestedQty: toD(json['suggested_qty']),
      cost: toD(json['cost']),
      lastUnitCost:
          json['last_unit_cost'] == null ? null : toD(json['last_unit_cost']),
      supplierId: json['suggested_supplier_id']?.toString(),
      supplierName: json['suggested_supplier_name']?.toString(),
    );
  }
}
