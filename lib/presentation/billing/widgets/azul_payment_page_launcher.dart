import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/responsive/dpi_scale.dart';
import '../../../domain/billing/billing_enums.dart';
import '../../theme/theme_data_factory.dart';
import '../viewmodel/billing_view_model.dart';

/// Botón que crea una sesión y abre la Azul Payment Page para registrar o
/// cambiar la tarjeta. Refleja el estado del flujo (`launching`/`verifying`).
class AzulPaymentPageLauncher extends ConsumerWidget {
  const AzulPaymentPageLauncher({
    super.key,
    required this.businessId,
    required this.intent,
    required this.label,
    this.icon = Icons.add_card_rounded,
    this.filled = true,
  });

  final String businessId;
  final CardIntent intent;
  final String label;
  final IconData icon;

  /// `true` → botón sólido (alta de tarjeta). `false` → outline (cambiar).
  final bool filled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dpi = DpiScale.of(context);
    final flow = ref.watch(billingViewModelProvider).cardFlow;
    final busy = flow == BillingCardFlow.launching || flow == BillingCardFlow.verifying;

    final child = busy
        ? SizedBox(
            height: dpi.icon(18),
            width: dpi.icon(18),
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(
                filled ? Colors.white : MangoThemeFactory.mango,
              ),
            ),
          )
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: dpi.icon(18)),
              SizedBox(width: dpi.space(8)),
              Text(label),
            ],
          );

    void onPressed() {
      ref
          .read(billingViewModelProvider.notifier)
          .startCardRegistration(businessId, intent: intent);
    }

    if (filled) {
      return SizedBox(
        width: double.infinity,
        child: FilledButton(
          onPressed: busy ? null : onPressed,
          style: FilledButton.styleFrom(
            backgroundColor: MangoThemeFactory.mango,
            foregroundColor: Colors.white,
            padding: EdgeInsets.symmetric(vertical: dpi.space(14)),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(dpi.radius(12)),
            ),
          ),
          child: child,
        ),
      );
    }

    return SizedBox(
      width: double.infinity,
      child: OutlinedButton(
        onPressed: busy ? null : onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: MangoThemeFactory.mango,
          side: const BorderSide(color: MangoThemeFactory.mango),
          padding: EdgeInsets.symmetric(vertical: dpi.space(12)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(dpi.radius(12)),
          ),
        ),
        child: child,
      ),
    );
  }
}
