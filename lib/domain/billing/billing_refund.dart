import 'package:flutter/foundation.dart';

import 'billing_enums.dart';

/// Reembolso aprobado de un cobro de suscripción, tal como lo expone la RPC
/// `fn_business_subscription_refunds` (mangopos_administrador 0047): solo
/// monto, cobro y fecha — nunca la razón interna ni datos de Azul.
@immutable
class BillingRefund {
  const BillingRefund({
    required this.id,
    required this.chargeId,
    required this.amountCents,
    required this.currencyCode,
    required this.refundedAt,
  });

  final String id;
  final String chargeId;
  final int amountCents;
  final String currencyCode;
  final DateTime? refundedAt;

  /// Monto reembolsado en pesos (DOP).
  double get amount => amountCents / 100.0;

  factory BillingRefund.fromJson(Map<String, dynamic> json) {
    return BillingRefund(
      id: json['id']?.toString() ?? '',
      chargeId: json['charge_id']?.toString() ?? '',
      amountCents: billingToInt(json['amount_cents']),
      currencyCode: json['currency_code']?.toString() ?? 'DOP',
      refundedAt: billingParseDate(json['refunded_at']),
    );
  }
}
