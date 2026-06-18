import 'package:flutter/material.dart';

import '../../../core/formatters/mango_formatters.dart';
import '../../../core/responsive/dpi_scale.dart';
import '../../../domain/billing/billing_charge.dart';
import '../../../domain/billing/billing_enums.dart';
import '../../theme/theme_data_factory.dart';
import 'billing_ui.dart';

/// Historial de cobros mensuales (vista `azul_charges_public`).
class ChargeHistoryList extends StatelessWidget {
  const ChargeHistoryList({super.key, required this.charges});

  final List<BillingCharge>? charges;

  @override
  Widget build(BuildContext context) {
    final dpi = DpiScale.of(context);
    final list = charges ?? const <BillingCharge>[];

    return BillingCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              BillingIconBadge(
                icon: Icons.receipt_long_rounded,
                color: MangoThemeFactory.warning,
              ),
              SizedBox(width: dpi.space(12)),
              Expanded(
                child: Text(
                  'Historial de cobros',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          SizedBox(height: dpi.space(8)),
          if (list.isEmpty)
            Padding(
              padding: EdgeInsets.symmetric(vertical: dpi.space(8)),
              child: Text(
                'Todavía no hay cobros registrados.',
                style: TextStyle(
                  fontSize: dpi.font(13),
                  color: MangoThemeFactory.mutedText(context),
                ),
              ),
            )
          else
            ...List.generate(list.length, (i) {
              final last = i == list.length - 1;
              return Column(
                children: [
                  _ChargeRow(charge: list[i]),
                  if (!last)
                    Divider(
                      height: dpi.space(18),
                      color: MangoThemeFactory.borderColor(context).withValues(alpha: 0.5),
                    ),
                ],
              );
            }),
        ],
      ),
    );
  }
}

class _ChargeRow extends StatelessWidget {
  const _ChargeRow({required this.charge});

  final BillingCharge charge;

  @override
  Widget build(BuildContext context) {
    final dpi = DpiScale.of(context);
    final color = _statusColor(charge.status);
    final date = charge.completedAt ?? charge.attemptedAt;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                MangoFormatters.currency(charge.amount),
                style: TextStyle(
                  fontSize: dpi.font(15),
                  fontWeight: FontWeight.w700,
                  color: MangoThemeFactory.textColor(context),
                ),
              ),
              SizedBox(height: dpi.space(3)),
              Text(
                date != null ? MangoFormatters.dateTime(date) : 'Fecha no disponible',
                style: TextStyle(
                  fontSize: dpi.font(11.5),
                  color: MangoThemeFactory.mutedText(context),
                ),
              ),
              if (charge.attemptNumber > 1 || (charge.responseMessage?.isNotEmpty ?? false))
                Padding(
                  padding: EdgeInsets.only(top: dpi.space(3)),
                  child: Text(
                    [
                      if (charge.attemptNumber > 1) 'Intento ${charge.attemptNumber}',
                      if (charge.responseMessage?.isNotEmpty ?? false) charge.responseMessage!,
                    ].join(' · '),
                    style: TextStyle(
                      fontSize: dpi.font(11),
                      color: MangoThemeFactory.mutedText(context),
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
          ),
        ),
        SizedBox(width: dpi.space(8)),
        BillingStatusBadge(label: charge.status.label, color: color),
      ],
    );
  }

  Color _statusColor(ChargeStatus status) {
    switch (status) {
      case ChargeStatus.approved:
        return MangoThemeFactory.success;
      case ChargeStatus.pending:
        return MangoThemeFactory.info;
      case ChargeStatus.declined:
      case ChargeStatus.error:
        return MangoThemeFactory.danger;
      case ChargeStatus.voided:
      case ChargeStatus.unknown:
        return const Color(0xFF9CA3AF);
    }
  }
}
