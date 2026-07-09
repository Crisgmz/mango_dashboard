import 'package:flutter/material.dart' show TimeOfDay;

import 'promotion_enums.dart';

/// Oferta/promoción (tabla `promotions`). Espejo del modelo del POS para que
/// ambos sistemas lean/escriban lo mismo. El dashboard edita las "simples"
/// (% / monto fijo); las especiales (BOGO/combo) se muestran pero no se editan
/// con el formulario "Completo" (solo activar/eliminar) para no perder datos.
class Promotion {
  const Promotion({
    required this.id,
    required this.name,
    required this.description,
    required this.discountType,
    required this.promoType,
    required this.discountValue,
    required this.minPurchase,
    required this.appliesTo,
    required this.targetScope,
    required this.targetIds,
    required this.daysOfWeek,
    required this.autoApply,
    required this.stackable,
    required this.priority,
    required this.buyQuantity,
    required this.payQuantity,
    required this.rewardQuantity,
    required this.startDate,
    required this.endDate,
    required this.startTime,
    required this.endTime,
    required this.isActive,
    required this.createdAt,
  });

  final String id;
  final String name;
  final String description;
  final DiscountType discountType;

  /// Tipo crudo (`promo_type`): puede ser 'percentage'/'fixed' o especiales
  /// ('bogo'/'bundle_price') creadas en el POS.
  final String promoType;
  final double discountValue;
  final double minPurchase;
  final AppliesTo appliesTo;
  final String? targetScope;
  final List<String> targetIds;

  /// Días (0=domingo … 6=sábado). Vacío o los 7 = todos los días.
  final List<int> daysOfWeek;
  final bool autoApply;
  final bool stackable;
  final int priority;

  /// Cantidades para promos especiales (2x1/BOGO) creadas en el POS. Se
  /// preservan al editar; el dashboard no las crea.
  final int? buyQuantity;
  final int? payQuantity;
  final int? rewardQuantity;
  final DateTime? startDate;
  final DateTime? endDate;
  final TimeOfDay? startTime;
  final TimeOfDay? endTime;
  final bool isActive;
  final DateTime createdAt;

  /// `true` si es % o monto fijo (editable con el formulario del dashboard).
  bool get isSimple => promoType == 'percentage' || promoType == 'fixed';

  bool get isPercentage => discountType == DiscountType.percentage;

  bool get appliesToEverything => appliesTo == AppliesTo.all;

  /// Etiqueta del tipo de oferta para tipos especiales (no % ni fijo).
  String get specialTypeLabel {
    switch (promoType) {
      case 'bogo':
        return (buyQuantity != null && payQuantity != null)
            ? '${buyQuantity}x$payQuantity'
            : '2x1';
      case 'bundle_price':
        return 'Combo';
      default:
        return 'Oferta';
    }
  }

  String get daysSummary {
    if (daysOfWeek.isEmpty || daysOfWeek.length >= 7) return 'Todos los días';
    final sorted = [...daysOfWeek]..sort();
    return sorted
        .where((d) => d >= 0 && d <= 6)
        .map((d) => kWeekdayLabels[d])
        .join(', ');
  }

  String get timeSummary {
    if (startTime == null || endTime == null) return 'Todo el día';
    return '${_fmt(startTime!)}–${_fmt(endTime!)}';
  }

  static String _fmt(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  factory Promotion.fromJson(Map<String, dynamic> map) {
    final targetScope = map['target_scope']?.toString();
    final appliesToRaw = map['applies_to']?.toString() ?? 'all';
    return Promotion(
      id: map['id']?.toString() ?? '',
      name: map['name']?.toString() ?? 'Oferta',
      description: map['description']?.toString() ?? '',
      discountType: DiscountType.fromRaw(map['discount_type']?.toString()),
      promoType: map['promo_type']?.toString() ??
          map['discount_type']?.toString() ??
          'percentage',
      discountValue: _toDouble(map['discount_value']),
      minPurchase: _toDouble(map['min_purchase']),
      appliesTo: AppliesTo.fromRaw(appliesToRaw),
      targetScope: (targetScope == null || targetScope.isEmpty) ? appliesToRaw : targetScope,
      targetIds: _toStringList(map['target_ids']),
      daysOfWeek: _toIntList(map['days_of_week']),
      autoApply: map['auto_apply'] != false,
      stackable: map['stackable'] == true,
      priority: _toInt(map['priority']) ?? 0,
      buyQuantity: _toInt(map['buy_quantity']),
      payQuantity: _toInt(map['pay_quantity']),
      rewardQuantity: _toInt(map['reward_quantity']),
      startDate: _parseDate(map['start_date']),
      endDate: _parseDate(map['end_date']),
      startTime: _parseTime(map['start_time']),
      endTime: _parseTime(map['end_time']),
      isActive: map['is_active'] != false,
      createdAt: _parseDate(map['created_at']) ?? DateTime.now(),
    );
  }

  static double _toDouble(dynamic v) {
    if (v is num) return v.toDouble();
    return double.tryParse(v?.toString() ?? '') ?? 0;
  }

  static int? _toInt(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString());
  }

  static DateTime? _parseDate(dynamic v) {
    if (v == null) return null;
    return DateTime.tryParse(v.toString());
  }

  static TimeOfDay? _parseTime(dynamic v) {
    final raw = v?.toString();
    if (raw == null || raw.isEmpty) return null;
    final parts = raw.split(':');
    if (parts.length < 2) return null;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h == null || m == null || h < 0 || h > 23 || m < 0 || m > 59) return null;
    return TimeOfDay(hour: h, minute: m);
  }

  static List<String> _toStringList(dynamic v) {
    if (v is List) {
      return v
          .map((e) => e?.toString() ?? '')
          .where((e) => e.isNotEmpty)
          .toList(growable: false);
    }
    return const [];
  }

  static List<int> _toIntList(dynamic v) {
    if (v is List) {
      return v
          .map((e) => e is num ? e.toInt() : int.tryParse(e?.toString() ?? ''))
          .whereType<int>()
          .toList(growable: false);
    }
    return const [];
  }
}
