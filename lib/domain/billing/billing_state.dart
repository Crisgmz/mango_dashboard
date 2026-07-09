import 'package:flutter/foundation.dart';

import 'billing_charge.dart';
import 'billing_enums.dart';
import 'billing_plan.dart';

/// Estado de suscripción del comercio: la fila ancla de `memberships`
/// (`is_billing_anchor = true`) más el plan y los últimos cargos.
///
/// Todas estas columnas las escribe el motor de cobro del POS; el dashboard
/// solo las lee para mostrar el estado (regla R3 del PRD: no mutar).
@immutable
class BillingState {
  const BillingState({
    required this.membershipId,
    required this.businessId,
    required this.plan,
    required this.status,
    required this.trialEndsAt,
    required this.currentPeriodStart,
    required this.currentPeriodEnd,
    required this.nextBillingDate,
    required this.consentGrantedAt,
    required this.currentAttemptNumber,
    required this.suspendedAt,
    required this.cancelledAt,
    required this.cancellationReason,
    required this.lastSuccessfulCharge,
    required this.lastFailedCharge,
  });

  final String membershipId;
  final String businessId;
  final BillingPlan? plan;
  final BillingStatus status;
  final DateTime? trialEndsAt;
  final DateTime? currentPeriodStart;
  final DateTime? currentPeriodEnd;
  final DateTime? nextBillingDate;
  final DateTime? consentGrantedAt;
  final int currentAttemptNumber;
  final DateTime? suspendedAt;
  final DateTime? cancelledAt;
  final String? cancellationReason;
  final BillingCharge? lastSuccessfulCharge;
  final BillingCharge? lastFailedCharge;

  bool get isTrial => status == BillingStatus.trial;
  bool get isActive => status == BillingStatus.active;
  bool get isPastDue => status == BillingStatus.pastDue;
  bool get isSuspended => status == BillingStatus.suspended;
  bool get isCancelled => status == BillingStatus.cancelled;

  /// Días restantes hasta el próximo cobro (negativo si ya venció). Null si no hay fecha.
  int? get daysUntilNextBilling => _daysFromToday(nextBillingDate);

  /// Días restantes de prueba. Null si no hay fecha de fin de trial.
  int? get daysUntilTrialEnds => _daysFromToday(trialEndsAt);

  /// Estado en el que un cobro manual ("Pagar ahora") tiene sentido — hay un
  /// período por cobrar y no está suspendida ni cancelada.
  bool get canAttemptCharge => isTrial || isActive || isPastDue;

  /// Horas hasta el próximo cobro (negativo si ya está vencido). Null sin fecha.
  int? get hoursUntilNextBilling {
    final d = nextBillingDate;
    if (d == null) return null;
    return d.difference(DateTime.now()).inHours;
  }

  /// El botón "Pagar ahora" se habilita SOLO dentro de las 48 h previas a la
  /// fecha de cobro (o si ya está vencida). El cobro automático (cron) no pasa
  /// por este gate. Igual criterio que el POS.
  bool get isWithinPayWindow {
    final h = hoursUntilNextBilling;
    return h != null && h <= 48;
  }

  static int? _daysFromToday(DateTime? date) {
    if (date == null) return null;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final target = DateTime(date.year, date.month, date.day);
    return target.difference(today).inDays;
  }

  factory BillingState.fromJson(Map<String, dynamic> json) {
    final planJson = json['plan'];
    final lastOk = json['last_successful_charge'];
    final lastFail = json['last_failed_charge'];
    return BillingState(
      membershipId: json['id']?.toString() ?? '',
      businessId: json['business_id']?.toString() ?? '',
      plan: planJson is Map<String, dynamic>
          ? BillingPlan.fromJson(planJson)
          : null,
      status: BillingStatus.fromRaw(json['billing_status']?.toString()),
      trialEndsAt: billingParseDate(json['trial_ends_at']),
      currentPeriodStart: billingParseDate(json['current_period_start']),
      currentPeriodEnd: billingParseDate(json['current_period_end']),
      nextBillingDate: billingParseDate(json['next_billing_date']),
      consentGrantedAt: billingParseDate(json['consent_granted_at']),
      currentAttemptNumber: billingToInt(json['current_attempt_number']),
      suspendedAt: billingParseDate(json['suspended_at']),
      cancelledAt: billingParseDate(json['cancelled_at']),
      cancellationReason: json['cancellation_reason']?.toString(),
      lastSuccessfulCharge: lastOk is Map<String, dynamic>
          ? BillingCharge.fromJson(lastOk)
          : null,
      lastFailedCharge: lastFail is Map<String, dynamic>
          ? BillingCharge.fromJson(lastFail)
          : null,
    );
  }
}
