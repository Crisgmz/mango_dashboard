import 'package:flutter/foundation.dart';

import 'billing_enums.dart';

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

  /// Monto total en pesos (DOP).
  double get amount => amountCents / 100.0;

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
