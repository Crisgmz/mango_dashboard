import 'package:flutter/foundation.dart';

import 'billing_enums.dart';

/// Respuesta de la Edge Function `azul-create-tokenization-session`: la sesión
/// de la Azul Payment Page que el dueño debe abrir para registrar su tarjeta.
@immutable
class TokenizationSession {
  const TokenizationSession({
    required this.sessionId,
    required this.orderNumber,
    required this.paymentPageUrl,
    required this.expiresAt,
    required this.reused,
  });

  final String sessionId;
  final String orderNumber;

  /// URL de la página hospedada por Azul (form auto-submit). Se abre en el navegador.
  final String paymentPageUrl;

  final DateTime? expiresAt;

  /// True si el backend reusó una sesión `pending` no expirada (idempotencia).
  final bool reused;

  factory TokenizationSession.fromJson(Map<String, dynamic> json) {
    return TokenizationSession(
      sessionId: json['session_id']?.toString() ?? '',
      orderNumber: json['order_number']?.toString() ?? '',
      paymentPageUrl: json['payment_page_url']?.toString() ?? '',
      expiresAt: billingParseDate(json['expires_at']),
      reused: json['reused'] == true,
    );
  }
}
