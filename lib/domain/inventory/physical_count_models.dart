import 'package:flutter/foundation.dart';

/// Sesión de conteo físico (tabla `physical_count_sessions`).
/// Workflow: draft → in_progress → completed (o cancelled).
@immutable
class CountSession {
  const CountSession({
    required this.id,
    required this.code,
    required this.status,
    required this.warehouseId,
    this.warehouseName,
    this.isBlind = false,
    this.notes,
    this.startedAt,
    this.completedAt,
  });

  final String id;

  /// Folio PC-YYYY-NNNNNN (lo asigna un trigger).
  final String code;
  final String status;
  final String warehouseId;
  final String? warehouseName;

  /// Modo ciego: el contador no ve la cantidad esperada.
  final bool isBlind;
  final String? notes;
  final DateTime? startedAt;
  final DateTime? completedAt;

  bool get isOpen => status == 'draft' || status == 'in_progress';

  String get statusLabel {
    switch (status) {
      case 'draft':
        return 'Borrador';
      case 'in_progress':
        return 'En curso';
      case 'completed':
        return 'Completado';
      case 'cancelled':
        return 'Cancelado';
      default:
        return status;
    }
  }

  factory CountSession.fromJson(Map<String, dynamic> json) {
    final wh = json['warehouses'];
    return CountSession(
      id: json['id']?.toString() ?? '',
      code: json['code']?.toString() ?? '',
      status: json['status']?.toString() ?? 'draft',
      warehouseId: json['warehouse_id']?.toString() ?? '',
      warehouseName:
          wh is Map<String, dynamic> ? wh['name']?.toString() : null,
      isBlind: json['is_blind'] == true,
      notes: json['notes']?.toString(),
      startedAt: DateTime.tryParse(json['started_at']?.toString() ?? ''),
      completedAt: DateTime.tryParse(json['completed_at']?.toString() ?? ''),
    );
  }
}

/// Línea de un conteo (tabla `physical_count_lines`): snapshot congelado vs.
/// lo contado físicamente.
@immutable
class CountLine {
  const CountLine({
    required this.id,
    required this.itemId,
    required this.snapshotQuantity,
    this.countedQuantity,
    this.itemName,
    this.unit,
    this.cost,
    this.notes,
    this.recountRequested = false,
  });

  final String id;
  final String itemId;
  final double snapshotQuantity;
  final double? countedQuantity;
  final String? itemName;
  final String? unit;

  /// Costo maestro del insumo, para valorar la varianza.
  final double? cost;
  final String? notes;
  final bool recountRequested;

  bool get isCounted => countedQuantity != null;

  /// Diferencia contado − sistema (null si aún no se cuenta).
  double? get variance =>
      countedQuantity == null ? null : countedQuantity! - snapshotQuantity;

  /// Varianza valorada al costo maestro.
  double? get varianceCost {
    final v = variance;
    if (v == null || cost == null) return null;
    return v * cost!;
  }

  factory CountLine.fromJson(Map<String, dynamic> json) {
    final item = json['inventory_items'];
    double toD(dynamic v) =>
        v is num ? v.toDouble() : double.tryParse(v?.toString() ?? '') ?? 0;
    return CountLine(
      id: json['id']?.toString() ?? '',
      itemId: json['item_id']?.toString() ?? '',
      snapshotQuantity: toD(json['snapshot_quantity']),
      countedQuantity: json['counted_quantity'] == null
          ? null
          : toD(json['counted_quantity']),
      itemName:
          item is Map<String, dynamic> ? item['name']?.toString() : null,
      unit: item is Map<String, dynamic> ? item['unit']?.toString() : null,
      cost: item is Map<String, dynamic> && item['cost'] != null
          ? toD(item['cost'])
          : null,
      notes: json['counter_notes']?.toString(),
      recountRequested: json['recount_requested'] == true,
    );
  }
}
