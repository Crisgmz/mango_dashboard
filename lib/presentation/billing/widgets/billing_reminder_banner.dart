import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/responsive/dpi_scale.dart';
import '../../auth/viewmodel/auth_gate_view_model.dart';
import '../../theme/theme_data_factory.dart';
import '../view/billing_view.dart';
import '../viewmodel/billing_reminder.dart';

/// Banner que aparece en el dashboard cuando se acerca la fecha de cobro / fin
/// de prueba, o hay pago pendiente. Tocarlo abre la pantalla de Suscripción.
/// Si no hay nada que avisar (o aún carga), no ocupa espacio.
class BillingReminderBanner extends ConsumerWidget {
  const BillingReminderBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final businessId = ref.watch(authGateViewModelProvider).profile?.businessId;
    if (businessId == null) return const SizedBox.shrink();

    final reminder = ref.watch(billingReminderProvider(businessId)).valueOrNull;
    if (reminder == null) return const SizedBox.shrink();

    final dpi = DpiScale.of(context);
    return Padding(
      padding: EdgeInsets.only(top: dpi.space(12)),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(dpi.radius(14)),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const BillingView()),
          ),
          child: Container(
            padding: EdgeInsets.all(dpi.space(12)),
            decoration: BoxDecoration(
              color: reminder.color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(dpi.radius(14)),
              border: Border.all(color: reminder.color.withValues(alpha: 0.4)),
            ),
            child: Row(
              children: [
                Icon(reminder.icon, color: reminder.color, size: dpi.icon(22)),
                SizedBox(width: dpi.space(12)),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        reminder.title,
                        style: TextStyle(
                          fontSize: dpi.font(13.5),
                          fontWeight: FontWeight.w700,
                          color: MangoThemeFactory.textColor(context),
                        ),
                      ),
                      SizedBox(height: dpi.space(2)),
                      Text(
                        reminder.message,
                        style: TextStyle(
                          fontSize: dpi.font(12),
                          height: 1.3,
                          color: MangoThemeFactory.mutedText(context),
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(width: dpi.space(8)),
                Icon(
                  Icons.chevron_right_rounded,
                  color: reminder.color,
                  size: dpi.icon(22),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
