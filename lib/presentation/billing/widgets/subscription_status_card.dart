import 'package:flutter/material.dart';

import '../../../core/formatters/mango_formatters.dart';
import '../../../core/responsive/dpi_scale.dart';
import '../../../domain/billing/billing_enums.dart';
import '../../../domain/billing/billing_state.dart';
import '../../theme/theme_data_factory.dart';
import 'billing_ui.dart';

/// Card que resume el estado de la suscripción: plan, estado de cobro,
/// próximo cargo / cuenta regresiva de prueba, y avisos de pago pendiente.
class SubscriptionStatusCard extends StatelessWidget {
  const SubscriptionStatusCard({super.key, required this.state});

  /// Fila ancla de billing. Null si el comercio aún no tiene suscripción.
  final BillingState? state;

  @override
  Widget build(BuildContext context) {
    final dpi = DpiScale.of(context);
    final s = state;

    if (s == null) {
      return BillingCard(
        child: Row(
          children: [
            BillingIconBadge(
              icon: Icons.workspace_premium_outlined,
              color: MangoThemeFactory.mutedText(context),
            ),
            SizedBox(width: dpi.space(12)),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Sin plan asignado',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  SizedBox(height: dpi.space(4)),
                  Text(
                    'Aún no hay una suscripción configurada para este negocio.',
                    style: TextStyle(
                      fontSize: dpi.font(12),
                      color: MangoThemeFactory.mutedText(context),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    final statusColor = billingStatusColor(s.status);
    final planName = s.plan?.name ?? 'Plan';

    return BillingCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              BillingIconBadge(
                icon: Icons.workspace_premium_rounded,
                color: MangoThemeFactory.mango,
              ),
              SizedBox(width: dpi.space(12)),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Plan', style: _labelStyle(context, dpi)),
                    Text(
                      planName,
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              ),
              BillingStatusBadge(label: s.status.label, color: statusColor),
            ],
          ),
          if (s.plan != null) ...[
            SizedBox(height: dpi.space(14)),
            _row(
              context,
              dpi,
              'Precio mensual',
              '${MangoFormatters.currency(s.plan!.priceMonthly)} / mes',
            ),
          ],
          ..._statusDetails(context, dpi, s),
        ],
      ),
    );
  }

  List<Widget> _statusDetails(BuildContext context, DpiScale dpi, BillingState s) {
    final widgets = <Widget>[];

    switch (s.status) {
      case BillingStatus.trial:
        final days = s.daysUntilTrialEnds;
        widgets.add(_row(
          context,
          dpi,
          'Prueba termina',
          s.trialEndsAt != null
              ? MangoFormatters.dateTime(s.trialEndsAt!) +
                  (days != null && days >= 0 ? ' · ${_daysLabel(days)}' : '')
              : '—',
        ));
        break;
      case BillingStatus.active:
        final days = s.daysUntilNextBilling;
        widgets.add(_row(
          context,
          dpi,
          'Próximo cobro',
          s.nextBillingDate != null
              ? MangoFormatters.dateTime(s.nextBillingDate!) +
                  (days != null && days >= 0 ? ' · ${_daysLabel(days)}' : '')
              : '—',
        ));
        break;
      case BillingStatus.pastDue:
        widgets.add(_row(
          context,
          dpi,
          'Próximo reintento',
          s.nextBillingDate != null ? MangoFormatters.dateTime(s.nextBillingDate!) : '—',
        ));
        widgets.add(SizedBox(height: dpi.space(12)));
        widgets.add(BillingNotice(
          color: MangoThemeFactory.warning,
          icon: Icons.error_outline_rounded,
          message: s.currentAttemptNumber > 0
              ? 'El último cobro fue declinado (intento ${s.currentAttemptNumber} de 3). '
                  'Revisa tu tarjeta para evitar la suspensión del servicio.'
              : 'Hay un cobro pendiente. Revisa tu método de pago.',
        ));
        break;
      case BillingStatus.suspended:
        widgets.add(SizedBox(height: dpi.space(12)));
        widgets.add(BillingNotice(
          color: MangoThemeFactory.danger,
          icon: Icons.lock_outline_rounded,
          message: 'Tu suscripción está suspendida por falta de pago. '
              'Actualiza tu tarjeta para reactivar el servicio.',
        ));
        break;
      case BillingStatus.cancelled:
        widgets.add(SizedBox(height: dpi.space(12)));
        widgets.add(BillingNotice(
          color: MangoThemeFactory.mutedText(context),
          icon: Icons.cancel_outlined,
          message: s.cancellationReason?.isNotEmpty == true
              ? 'Suscripción cancelada: ${s.cancellationReason}'
              : 'Suscripción cancelada.',
        ));
        break;
      case BillingStatus.unknown:
        break;
    }
    return widgets;
  }

  String _daysLabel(int days) {
    if (days == 0) return 'hoy';
    if (days == 1) return 'en 1 día';
    return 'en $days días';
  }

  Widget _row(BuildContext context, DpiScale dpi, String label, String value) {
    return Padding(
      padding: EdgeInsets.only(top: dpi.space(8)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: Text(label, style: _labelStyle(context, dpi))),
          SizedBox(width: dpi.space(8)),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: dpi.font(13),
                fontWeight: FontWeight.w600,
                color: MangoThemeFactory.textColor(context),
              ),
            ),
          ),
        ],
      ),
    );
  }

  TextStyle _labelStyle(BuildContext context, DpiScale dpi) => TextStyle(
        fontSize: dpi.font(12),
        color: MangoThemeFactory.mutedText(context),
      );
}
