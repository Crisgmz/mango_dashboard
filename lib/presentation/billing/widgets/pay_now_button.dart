import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/formatters/mango_formatters.dart';
import '../../../core/responsive/dpi_scale.dart';
import '../../../domain/billing/billing_state.dart';
import '../../theme/theme_data_factory.dart';
import '../viewmodel/billing_view_model.dart';
import 'billing_ui.dart';

/// Botón "Pagar ahora" — cobro manual de la suscripción con la tarjeta default.
///
/// Solo se HABILITA dentro de las 48 h previas a la fecha de cobro (o si ya está
/// vencida) — ver [BillingState.isWithinPayWindow]. Fuera de esa ventana muestra
/// una nota con la fecha en que se habilita. El cobro automático (cron) NO pasa
/// por aquí. Reusa la Edge Function `azul-charge-now` (mismo backend que el POS).
class PayNowButton extends ConsumerWidget {
  const PayNowButton({
    super.key,
    required this.businessId,
    required this.state,
  });

  final String businessId;
  final BillingState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dpi = DpiScale.of(context);

    // Gate de 48 h: fuera de la ventana, una nota en vez del botón.
    if (!state.isWithinPayWindow) {
      final next = state.nextBillingDate;
      final when = next != null
          ? 'El pago se habilita 48 horas antes de tu fecha de cobro '
                '(${MangoFormatters.date(next)}).'
          : 'El pago manual se habilitará cerca de tu fecha de cobro.';
      return BillingNotice(
        color: MangoThemeFactory.mutedText(context),
        icon: Icons.lock_clock_rounded,
        message: when,
      );
    }

    final isCharging = ref.watch(
      billingViewModelProvider.select((s) => s.isCharging),
    );
    final amount = state.plan != null
        ? MangoFormatters.currency(state.plan!.priceMonthly)
        : null;

    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        onPressed: isCharging
            ? null
            : () => _confirmAndPay(context, ref, amount),
        style: FilledButton.styleFrom(
          backgroundColor: MangoThemeFactory.mango,
          foregroundColor: Colors.white,
          padding: EdgeInsets.symmetric(vertical: dpi.space(14)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(dpi.radius(12)),
          ),
        ),
        icon: isCharging
            ? SizedBox(
                width: dpi.icon(18),
                height: dpi.icon(18),
                child: const CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : Icon(Icons.bolt_rounded, size: dpi.icon(20)),
        label: Text(
          isCharging
              ? 'Procesando…'
              : (amount != null ? 'Pagar ahora · $amount' : 'Pagar ahora'),
          style: TextStyle(fontSize: dpi.font(15), fontWeight: FontWeight.w700),
        ),
      ),
    );
  }

  Future<void> _confirmAndPay(
    BuildContext context,
    WidgetRef ref,
    String? amount,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Pagar suscripción'),
        content: Text(
          amount == null
              ? '¿Cobrar tu suscripción ahora con la tarjeta registrada?'
              : 'Se cobrará $amount a tu tarjeta registrada. ¿Continuar?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: MangoThemeFactory.mango,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Pagar ahora'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final result = await ref
        .read(billingViewModelProvider.notifier)
        .chargeNow(businessId);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(result.message),
        backgroundColor: result.success
            ? MangoThemeFactory.success
            : MangoThemeFactory.danger,
      ),
    );
  }
}
