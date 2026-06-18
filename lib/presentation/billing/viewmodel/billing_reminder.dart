import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/di/providers.dart';
import '../../../core/formatters/mango_formatters.dart';
import '../../../domain/billing/billing_enums.dart';
import '../../../domain/billing/billing_payment_method.dart';
import '../../../domain/billing/billing_state.dart';
import '../../theme/theme_data_factory.dart';

/// Gravedad del recordatorio, que define color e ícono.
enum BillingReminderSeverity { info, warning, danger }

/// Aviso de cobro próximo / pendiente listo para mostrar (banner o popup).
@immutable
class BillingReminder {
  const BillingReminder({
    required this.severity,
    required this.title,
    required this.message,
    required this.needsCard,
  });

  final BillingReminderSeverity severity;
  final String title;
  final String message;

  /// El CTA debería llevar a registrar/cambiar tarjeta.
  final bool needsCard;

  Color get color {
    switch (severity) {
      case BillingReminderSeverity.info:
        return MangoThemeFactory.info;
      case BillingReminderSeverity.warning:
        return MangoThemeFactory.warning;
      case BillingReminderSeverity.danger:
        return MangoThemeFactory.danger;
    }
  }

  IconData get icon {
    switch (severity) {
      case BillingReminderSeverity.info:
        return Icons.event_available_rounded;
      case BillingReminderSeverity.warning:
        return Icons.access_time_rounded;
      case BillingReminderSeverity.danger:
        return Icons.error_outline_rounded;
    }
  }
}

/// Cuántos días antes del cobro / fin de prueba empieza a avisar.
const int kBillingReminderDays = 5;

/// Construye el recordatorio a mostrar (o null si no aplica) a partir del
/// estado de suscripción y si hay una tarjeta verificada.
BillingReminder? computeBillingReminder(
  BillingState? state, {
  required bool hasVerifiedCard,
  int thresholdDays = kBillingReminderDays,
}) {
  if (state == null) return null;

  switch (state.status) {
    case BillingStatus.suspended:
      return const BillingReminder(
        severity: BillingReminderSeverity.danger,
        title: 'Suscripción suspendida',
        message: 'Tu servicio está suspendido por falta de pago. '
            'Actualiza tu tarjeta para reactivarlo.',
        needsCard: true,
      );

    case BillingStatus.pastDue:
      final attempt = state.currentAttemptNumber;
      return BillingReminder(
        severity: BillingReminderSeverity.danger,
        title: 'Tienes un pago pendiente',
        message: attempt > 0
            ? 'El último cobro fue declinado (intento $attempt de 3). '
                'Revisa tu tarjeta para evitar la suspensión del servicio.'
            : 'Hay un cobro pendiente. Revisa tu método de pago.',
        needsCard: true,
      );

    case BillingStatus.trial:
      final days = state.daysUntilTrialEnds;
      if (days == null || days < 0 || days > thresholdDays) return null;
      return BillingReminder(
        severity: hasVerifiedCard
            ? BillingReminderSeverity.info
            : BillingReminderSeverity.warning,
        title: 'Tu prueba está por terminar',
        message: 'Tu período de prueba termina ${_whenLabel(days)}'
            '${_dateSuffix(state.trialEndsAt)}. '
            '${hasVerifiedCard ? 'Tu suscripción continuará automáticamente.' : 'Registra una tarjeta para no perder el servicio.'}',
        needsCard: !hasVerifiedCard,
      );

    case BillingStatus.active:
      final days = state.daysUntilNextBilling;
      if (days == null || days < 0 || days > thresholdDays) return null;
      final price = state.plan?.priceMonthly;
      final amount = price != null ? ' de ${MangoFormatters.currency(price)}' : '';
      return BillingReminder(
        severity: hasVerifiedCard
            ? BillingReminderSeverity.info
            : BillingReminderSeverity.warning,
        title: 'Próximo cobro',
        message: 'Tu próximo cobro$amount es ${_whenLabel(days)}'
            '${_dateSuffix(state.nextBillingDate)}.'
            '${hasVerifiedCard ? '' : ' Registra una tarjeta para evitar interrupciones.'}',
        needsCard: !hasVerifiedCard,
      );

    case BillingStatus.cancelled:
    case BillingStatus.unknown:
      return null;
  }
}

String _whenLabel(int days) {
  if (days <= 0) return 'hoy';
  if (days == 1) return 'mañana';
  return 'en $days días';
}

String _dateSuffix(DateTime? date) {
  if (date == null) return '';
  final local = date.toLocal();
  return ' (${local.day.toString().padLeft(2, '0')}/${local.month.toString().padLeft(2, '0')}/${local.year})';
}

/// Recordatorio de cobro para el negocio activo. Cacheado por sesión (por
/// `businessId`); refresca al reiniciar el app o al invalidar el provider.
final billingReminderProvider =
    FutureProvider.family<BillingReminder?, String>((ref, businessId) async {
  final service = ref.read(billingDataServiceProvider);
  final results = await Future.wait([
    service.getBillingState(businessId),
    service.getDefaultPaymentMethod(businessId),
  ]);
  final state = results[0] as BillingState?;
  final card = results[1] as BillingPaymentMethod?;
  return computeBillingReminder(state, hasVerifiedCard: card?.isVerified ?? false);
});
