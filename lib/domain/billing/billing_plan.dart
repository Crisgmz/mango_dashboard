import 'package:flutter/foundation.dart';

import 'billing_enums.dart';

/// Plan del catálogo del POS (`plans`). El precio del cobro recurrente sale de
/// `price_cents_monthly`. El dashboard solo lo lee (vía join con `memberships`).
@immutable
class BillingPlan {
  const BillingPlan({
    required this.id,
    required this.code,
    required this.name,
    required this.priceCentsMonthly,
    required this.currencyCode,
    required this.features,
    required this.trialDays,
    required this.isActive,
  });

  final String id;
  final String code;
  final String name;
  final int priceCentsMonthly;
  final String currencyCode;
  final List<String> features;
  final int trialDays;
  final bool isActive;

  /// Precio mensual en pesos (DOP), derivado de los centavos.
  double get priceMonthly => priceCentsMonthly / 100.0;

  factory BillingPlan.fromJson(Map<String, dynamic> json) {
    final rawFeatures = json['features'];
    final features = <String>[];
    if (rawFeatures is List) {
      for (final f in rawFeatures) {
        final s = f?.toString().trim();
        if (s != null && s.isNotEmpty) features.add(s);
      }
    }
    return BillingPlan(
      id: json['id']?.toString() ?? '',
      code: json['code']?.toString() ?? '',
      name: json['name']?.toString() ?? json['code']?.toString() ?? 'Plan',
      priceCentsMonthly: billingToInt(json['price_cents_monthly']),
      currencyCode: json['currency_code']?.toString() ?? 'DOP',
      features: features,
      trialDays: billingToInt(json['trial_days']),
      isActive: json['is_active'] == true,
    );
  }
}
