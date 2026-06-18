import 'package:flutter/material.dart';

import '../../../core/responsive/dpi_scale.dart';
import '../../../domain/billing/billing_enums.dart';
import '../../../domain/billing/billing_payment_method.dart';
import '../../theme/theme_data_factory.dart';
import 'azul_payment_page_launcher.dart';
import 'billing_ui.dart';

/// Card del método de pago: muestra la tarjeta registrada (marca, ••••últimos 4,
/// vencimiento, estado) o un estado vacío, con el botón para registrar/cambiar.
class PaymentMethodCard extends StatelessWidget {
  const PaymentMethodCard({
    super.key,
    required this.businessId,
    required this.method,
  });

  final String businessId;
  final BillingPaymentMethod? method;

  @override
  Widget build(BuildContext context) {
    final dpi = DpiScale.of(context);
    final pm = method;

    return BillingCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              BillingIconBadge(
                icon: Icons.credit_card_rounded,
                color: MangoThemeFactory.info,
              ),
              SizedBox(width: dpi.space(12)),
              Expanded(
                child: Text(
                  'Método de pago',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              if (pm != null) _statusBadge(context, pm),
            ],
          ),
          SizedBox(height: dpi.space(14)),
          if (pm == null)
            _empty(context, dpi)
          else
            _cardRow(context, dpi, pm),
          SizedBox(height: dpi.space(14)),
          AzulPaymentPageLauncher(
            businessId: businessId,
            intent: pm == null ? CardIntent.tokenizeAndVerify : CardIntent.replaceCard,
            label: pm == null ? 'Agregar tarjeta' : 'Cambiar tarjeta',
            icon: pm == null ? Icons.add_card_rounded : Icons.sync_rounded,
            filled: pm == null,
          ),
          SizedBox(height: dpi.space(8)),
          Text(
            'El registro se realiza en la página segura de Azul. '
            'MangoPOS nunca almacena el número de tu tarjeta.',
            style: TextStyle(
              fontSize: dpi.font(11),
              color: MangoThemeFactory.mutedText(context),
              height: 1.3,
            ),
          ),
        ],
      ),
    );
  }

  Widget _empty(BuildContext context, DpiScale dpi) {
    return Text(
      'No hay una tarjeta registrada. Agrega una para mantener tu suscripción activa.',
      style: TextStyle(
        fontSize: dpi.font(13),
        color: MangoThemeFactory.mutedText(context),
        height: 1.35,
      ),
    );
  }

  Widget _cardRow(BuildContext context, DpiScale dpi, BillingPaymentMethod pm) {
    final brand = pm.brand.isEmpty ? 'Tarjeta' : pm.brand;
    return Row(
      children: [
        Container(
          padding: EdgeInsets.symmetric(horizontal: dpi.space(10), vertical: dpi.space(8)),
          decoration: BoxDecoration(
            color: MangoThemeFactory.altSurface(context),
            borderRadius: BorderRadius.circular(dpi.radius(8)),
          ),
          child: Text(
            brand.toUpperCase(),
            style: TextStyle(
              fontSize: dpi.font(11),
              fontWeight: FontWeight.w800,
              letterSpacing: 0.5,
              color: MangoThemeFactory.textColor(context),
            ),
          ),
        ),
        SizedBox(width: dpi.space(12)),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '•••• ${pm.last4}',
                style: TextStyle(
                  fontSize: dpi.font(16),
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.5,
                  color: MangoThemeFactory.textColor(context),
                ),
              ),
              if (pm.expiration.isNotEmpty)
                Text(
                  'Vence ${pm.expirationLabel}',
                  style: TextStyle(
                    fontSize: dpi.font(12),
                    color: MangoThemeFactory.mutedText(context),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _statusBadge(BuildContext context, BillingPaymentMethod pm) {
    if (pm.isVerified) {
      return const BillingStatusBadge(
        label: 'Verificada',
        color: MangoThemeFactory.success,
      );
    }
    if (pm.status == PaymentMethodStatus.pendingVerification) {
      return const BillingStatusBadge(
        label: 'Pendiente',
        color: MangoThemeFactory.warning,
      );
    }
    return const BillingStatusBadge(
      label: 'No válida',
      color: MangoThemeFactory.danger,
    );
  }
}
