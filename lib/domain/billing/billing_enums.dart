/// Estado de cobro de la suscripción SaaS (fila ancla de `memberships`).
/// Lo escribe el motor de cobro del POS; el dashboard solo lo muestra.
enum BillingStatus {
  trial,
  active,
  pastDue,
  suspended,
  cancelled,
  unknown;

  static BillingStatus fromRaw(String? raw) {
    switch (raw?.trim().toLowerCase()) {
      case 'trial':
        return BillingStatus.trial;
      case 'active':
        return BillingStatus.active;
      case 'past_due':
      case 'pastdue':
        return BillingStatus.pastDue;
      case 'suspended':
        return BillingStatus.suspended;
      case 'cancelled':
      case 'canceled':
        return BillingStatus.cancelled;
      default:
        return BillingStatus.unknown;
    }
  }

  String get label {
    switch (this) {
      case BillingStatus.trial:
        return 'Prueba';
      case BillingStatus.active:
        return 'Al día';
      case BillingStatus.pastDue:
        return 'Pago pendiente';
      case BillingStatus.suspended:
        return 'Suspendida';
      case BillingStatus.cancelled:
        return 'Cancelada';
      case BillingStatus.unknown:
        return 'Sin estado';
    }
  }
}

/// Estado de verificación de una tarjeta tokenizada (`azul_payment_methods.status`).
enum PaymentMethodStatus {
  pendingVerification,
  verified,
  failedVerification,
  expired,
  revoked,
  unknown;

  static PaymentMethodStatus fromRaw(String? raw) {
    switch (raw?.trim().toLowerCase()) {
      case 'pending_verification':
        return PaymentMethodStatus.pendingVerification;
      case 'verified':
        return PaymentMethodStatus.verified;
      case 'failed_verification':
        return PaymentMethodStatus.failedVerification;
      case 'expired':
        return PaymentMethodStatus.expired;
      case 'revoked':
        return PaymentMethodStatus.revoked;
      default:
        return PaymentMethodStatus.unknown;
    }
  }

  bool get isVerified => this == PaymentMethodStatus.verified;
}

/// Resultado de un intento de cobro mensual (`azul_charges.status`).
enum ChargeStatus {
  pending,
  approved,
  declined,
  error,
  voided,
  unknown;

  static ChargeStatus fromRaw(String? raw) {
    switch (raw?.trim().toLowerCase()) {
      case 'pending':
        return ChargeStatus.pending;
      case 'approved':
        return ChargeStatus.approved;
      case 'declined':
        return ChargeStatus.declined;
      case 'error':
        return ChargeStatus.error;
      case 'voided':
        return ChargeStatus.voided;
      default:
        return ChargeStatus.unknown;
    }
  }

  bool get isApproved => this == ChargeStatus.approved;

  String get label {
    switch (this) {
      case ChargeStatus.pending:
        return 'En proceso';
      case ChargeStatus.approved:
        return 'Aprobado';
      case ChargeStatus.declined:
        return 'Declinado';
      case ChargeStatus.error:
        return 'Error';
      case ChargeStatus.voided:
        return 'Anulado';
      case ChargeStatus.unknown:
        return 'Desconocido';
    }
  }
}

/// Intención al abrir la Azul Payment Page.
enum CardIntent {
  /// Alta de una tarjeta nueva.
  tokenizeAndVerify,

  /// Reemplazo de la tarjeta default existente.
  replaceCard;

  String get raw {
    switch (this) {
      case CardIntent.tokenizeAndVerify:
        return 'tokenize_and_verify';
      case CardIntent.replaceCard:
        return 'replace_card';
    }
  }
}

/// Convierte un valor dinámico de Supabase a `int` de forma segura.
int billingToInt(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

/// Parsea un timestamp ISO de Supabase a `DateTime?` (null-safe).
DateTime? billingParseDate(dynamic value) {
  final raw = value?.toString();
  if (raw == null || raw.isEmpty) return null;
  return DateTime.tryParse(raw);
}
