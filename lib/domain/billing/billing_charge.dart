import 'package:flutter/foundation.dart';

import 'billing_enums.dart';
import 'billing_refund.dart';

/// Intento de cobro mensual, leído desde la vista `azul_charges_public`.
/// La vista oculta `raw_request`/`raw_response` y otros datos técnicos.
@immutable
class BillingCharge {
  const BillingCharge({
    required this.id,
    required this.orderNumber,
    required this.billingPeriodStart,
    required this.billingPeriodEnd,
    required this.attemptNumber,
    required this.amountCents,
    required this.itbisCents,
    required this.currencyCode,
    required this.status,
    required this.responseMessage,
    required this.authorizationCode,
    required this.rrn,
    required this.attemptedAt,
    required this.completedAt,
    required this.receiptPdfPath,
    this.refunds = const [],
  });

  final String id;
  final String orderNumber;
  final DateTime? billingPeriodStart;
  final DateTime? billingPeriodEnd;
  final int attemptNumber;
  final int amountCents;
  final int itbisCents;
  final String currencyCode;
  final ChargeStatus status;
  final String? responseMessage;
  final String? authorizationCode;
  final String? rrn;
  final DateTime? attemptedAt;
  final DateTime? completedAt;
  final String? receiptPdfPath;

  /// Reembolsos aprobados de este cobro (más reciente primero).
  final List<BillingRefund> refunds;

  /// Monto total en pesos (DOP).
  double get amount => amountCents / 100.0;

  int get refundedCents =>
      refunds.fold(0, (sum, r) => sum + r.amountCents);

  /// Reembolsado en pesos (DOP).
  double get refunded => refundedCents / 100.0;

  bool get hasRefund => refundedCents > 0;
  bool get isFullyRefunded => hasRefund && refundedCents >= amountCents;

  /// Lo que finalmente se pagó: cobrado − reembolsado.
  double get netAmount =>
      (amountCents - refundedCents).clamp(0, amountCents) / 100.0;

  BillingCharge withRefunds(List<BillingRefund> refunds) => BillingCharge(
        id: id,
        orderNumber: orderNumber,
        billingPeriodStart: billingPeriodStart,
        billingPeriodEnd: billingPeriodEnd,
        attemptNumber: attemptNumber,
        amountCents: amountCents,
        itbisCents: itbisCents,
        currencyCode: currencyCode,
        status: status,
        responseMessage: responseMessage,
        authorizationCode: authorizationCode,
        rrn: rrn,
        attemptedAt: attemptedAt,
        completedAt: completedAt,
        receiptPdfPath: receiptPdfPath,
        refunds: refunds,
      );

  /// ITBIS en pesos (DOP).
  double get itbis => itbisCents / 100.0;

  bool get hasReceipt => (receiptPdfPath ?? '').isNotEmpty;

  factory BillingCharge.fromJson(Map<String, dynamic> json) {
    return BillingCharge(
      id: json['id']?.toString() ?? '',
      orderNumber: json['order_number']?.toString() ?? '',
      billingPeriodStart: billingParseDate(json['billing_period_start']),
      billingPeriodEnd: billingParseDate(json['billing_period_end']),
      attemptNumber: billingToInt(json['attempt_number']),
      amountCents: billingToInt(json['amount_cents']),
      itbisCents: billingToInt(json['itbis_cents']),
      currencyCode: json['currency_code']?.toString() ?? 'DOP',
      status: ChargeStatus.fromRaw(json['status']?.toString()),
      responseMessage: json['response_message']?.toString(),
      authorizationCode: json['authorization_code']?.toString(),
      rrn: json['rrn']?.toString(),
      attemptedAt: billingParseDate(json['attempted_at']),
      completedAt: billingParseDate(json['completed_at']),
      receiptPdfPath: json['receipt_pdf_path']?.toString(),
    );
  }
}

/// Reparte [refunds] entre sus cobros. Un reembolso cuyo cobro no está en la
/// lista (fuera del límite del historial) se ignora.
List<BillingCharge> attachRefunds(
  List<BillingCharge> charges,
  List<BillingRefund> refunds,
) {
  if (refunds.isEmpty) return charges;
  final byCharge = <String, List<BillingRefund>>{};
  for (final r in refunds) {
    byCharge.putIfAbsent(r.chargeId, () => []).add(r);
  }
  return [
    for (final c in charges)
      byCharge[c.id] == null ? c : c.withRefunds(List.unmodifiable(byCharge[c.id]!)),
  ];
}

/// Reembolso más reciente hecho en los últimos [days] días, con su cobro.
/// Es el que se avisa arriba en la pantalla de suscripción; los viejos solo
/// quedan en el historial.
({BillingRefund refund, BillingCharge charge})? latestRecentRefund(
  List<BillingCharge> charges, {
  DateTime? now,
  int days = 30,
}) {
  final cutoff = (now ?? DateTime.now()).subtract(Duration(days: days));
  ({BillingRefund refund, BillingCharge charge})? best;
  for (final c in charges) {
    for (final r in c.refunds) {
      final at = r.refundedAt;
      if (at == null || at.isBefore(cutoff)) continue;
      if (best == null || at.isAfter(best.refund.refundedAt!)) {
        best = (refund: r, charge: c);
      }
    }
  }
  return best;
}
