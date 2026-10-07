import 'package:flutter/foundation.dart';

/// Valoración de un artículo (vista `v_inventory_valuation_summary`):
/// valor a costo + clase ABC por participación acumulada en el valor total
/// (A ≤20% · B ≤50% · C resto).
@immutable
class ValuationItem {
  const ValuationItem({
    required this.itemId,
    required this.name,
    required this.unit,
    required this.totalQuantity,
    required this.totalValue,
    this.abcClass,
    this.cumulativePct,
    this.lastMovementAt,
  });

  final String itemId;
  final String name;
  final String unit;
  final double totalQuantity;
  final double totalValue;

  /// 'A' | 'B' | 'C' | 'no_data'.
  final String? abcClass;
  final double? cumulativePct;
  final DateTime? lastMovementAt;

  factory ValuationItem.fromJson(Map<String, dynamic> json) {
    double toD(dynamic v) =>
        v is num ? v.toDouble() : double.tryParse(v?.toString() ?? '') ?? 0;
    return ValuationItem(
      itemId: json['item_id']?.toString() ?? '',
      name: json['item_name']?.toString() ?? 'Artículo',
      unit: json['item_unit']?.toString() ?? 'unidad',
      totalQuantity: toD(json['total_quantity']),
      totalValue: toD(json['total_value']),
      abcClass: json['abc_class']?.toString(),
      cumulativePct: json['cumulative_pct'] == null
          ? null
          : toD(json['cumulative_pct']),
      lastMovementAt:
          DateTime.tryParse(json['last_movement_at']?.toString() ?? ''),
    );
  }
}

/// Análisis de rotación de un artículo (`fn_inventory_rotation_analysis`):
/// velocidad de salida y días de cobertura del período analizado.
@immutable
class RotationItem {
  const RotationItem({
    required this.itemId,
    required this.name,
    required this.unit,
    required this.currentStock,
    required this.outflowQty,
    required this.outflowPerDay,
    required this.rotationClass,
    this.daysOfSupply,
    this.outflowValue = 0,
  });

  final String itemId;
  final String name;
  final String unit;
  final double currentStock;
  final double outflowQty;
  final double outflowPerDay;

  /// 'star' (top 20% de salida) | 'active' | 'slow' | 'dormant' (sin salida).
  final String rotationClass;
  final double? daysOfSupply;
  final double outflowValue;

  String get classLabel {
    switch (rotationClass) {
      case 'star':
        return 'Estrella';
      case 'active':
        return 'Activo';
      case 'slow':
        return 'Lento';
      case 'dormant':
        return 'Dormido';
      default:
        return rotationClass;
    }
  }

  factory RotationItem.fromJson(Map<String, dynamic> json) {
    double toD(dynamic v) =>
        v is num ? v.toDouble() : double.tryParse(v?.toString() ?? '') ?? 0;
    return RotationItem(
      itemId: json['item_id']?.toString() ?? '',
      name: json['item_name']?.toString() ?? 'Artículo',
      unit: json['item_unit']?.toString() ?? 'unidad',
      currentStock: toD(json['current_stock']),
      outflowQty: toD(json['outflow_qty']),
      outflowPerDay: toD(json['outflow_per_day']),
      rotationClass: json['rotation_class']?.toString() ?? 'slow',
      daysOfSupply: json['days_of_supply'] == null
          ? null
          : toD(json['days_of_supply']),
      outflowValue: toD(json['outflow_value']),
    );
  }
}

/// Un movimiento de merma (kardex con motivo de pérdida): salida por rotura,
/// vencimiento, robo/pérdida o donación, valorada a costo.
@immutable
class WasteEntry {
  const WasteEntry({
    required this.itemId,
    required this.name,
    required this.unit,
    required this.reasonCode,
    required this.quantity,
    required this.value,
    this.createdAt,
  });

  final String itemId;
  final String name;
  final String unit;

  /// 'breakage' | 'expiration' | 'theft' | 'donation'.
  final String reasonCode;

  /// Unidades perdidas (absoluto, siempre positivo).
  final double quantity;

  /// Costo de lo perdido: |cantidad| × costo del movimiento.
  final double value;
  final DateTime? createdAt;

  static String reasonLabel(String code) {
    switch (code) {
      case 'breakage':
        return 'Rotura';
      case 'expiration':
        return 'Vencido';
      case 'theft':
        return 'Robo / pérdida';
      case 'donation':
        return 'Donación';
      default:
        return 'Otro';
    }
  }

  factory WasteEntry.fromJson(Map<String, dynamic> json) {
    double toD(dynamic v) =>
        v is num ? v.toDouble() : double.tryParse(v?.toString() ?? '') ?? 0;
    return WasteEntry(
      itemId: json['item_id']?.toString() ?? '',
      name: json['item_name']?.toString() ?? 'Artículo',
      unit: json['item_unit']?.toString() ?? 'unidad',
      reasonCode: json['reason_code']?.toString() ?? 'other',
      quantity: toD(json['quantity']).abs(),
      value: toD(json['total_value']),
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? ''),
    );
  }
}
