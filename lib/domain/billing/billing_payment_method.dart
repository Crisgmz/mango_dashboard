import 'package:flutter/foundation.dart';

import 'billing_enums.dart';

/// Tarjeta tokenizada del comercio, leída desde la vista `azul_payment_methods_public`.
/// La vista NUNCA expone `data_vault_token`; aquí solo viven datos seguros.
@immutable
class BillingPaymentMethod {
  const BillingPaymentMethod({
    required this.id,
    required this.businessId,
    required this.brand,
    required this.cardNumberMasked,
    required this.expiration,
    required this.status,
    required this.isDefault,
    required this.createdAt,
    required this.revokedAt,
  });

  final String id;
  final String businessId;

  /// Marca (VISA, MASTERCARD, AMEX…).
  final String brand;

  /// Número enmascarado tal como lo entrega Azul (p. ej. `****1234`).
  final String cardNumberMasked;

  /// Vencimiento en formato `AAAAMM`.
  final String expiration;

  final PaymentMethodStatus status;
  final bool isDefault;
  final DateTime? createdAt;
  final DateTime? revokedAt;

  bool get isVerified => status.isVerified;

  /// Últimos 4 dígitos extraídos del número enmascarado.
  String get last4 {
    final digits = cardNumberMasked.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length >= 4) return digits.substring(digits.length - 4);
    return digits;
  }

  /// Vencimiento legible `MM/AA` a partir de `AAAAMM`.
  String get expirationLabel {
    if (expiration.length == 6) {
      final year = expiration.substring(0, 4);
      final month = expiration.substring(4, 6);
      return '$month/${year.substring(2)}';
    }
    return expiration;
  }

  factory BillingPaymentMethod.fromJson(Map<String, dynamic> json) {
    return BillingPaymentMethod(
      id: json['id']?.toString() ?? '',
      businessId: json['business_id']?.toString() ?? '',
      brand: json['data_vault_brand']?.toString() ?? '',
      cardNumberMasked: json['card_number_masked']?.toString() ?? '',
      expiration: json['data_vault_expiration']?.toString() ?? '',
      status: PaymentMethodStatus.fromRaw(json['status']?.toString()),
      isDefault: json['is_default'] == true,
      createdAt: billingParseDate(json['created_at']),
      revokedAt: billingParseDate(json['revoked_at']),
    );
  }
}
