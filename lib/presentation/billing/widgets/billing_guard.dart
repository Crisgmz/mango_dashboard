import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/di/providers.dart';
import '../../../core/responsive/dpi_scale.dart';
import '../../../domain/billing/billing_enums.dart';
import '../../../domain/billing/billing_payment_method.dart';
import '../../../domain/billing/billing_state.dart';
import '../../auth/viewmodel/auth_gate_view_model.dart';
import '../../theme/theme_data_factory.dart';
import 'azul_payment_page_launcher.dart';
import 'billing_ui.dart';

/// Datos mínimos que necesita el guard para decidir si bloquea.
class _GuardData {
  const _GuardData(this.state, this.card);
  final BillingState? state;
  final BillingPaymentMethod? card;
}

final _guardDataProvider = FutureProvider.family<_GuardData, String>((ref, businessId) async {
  final service = ref.read(billingDataServiceProvider);
  final results = await Future.wait([
    service.getBillingState(businessId),
    service.getDefaultPaymentMethod(businessId),
  ]);
  return _GuardData(
    results[0] as BillingState?,
    results[1] as BillingPaymentMethod?,
  );
});

/// Envuelve el shell y, cuando está habilitado, bloquea el acceso a comercios
/// `suspended` o en `trial` sin tarjeta verificada.
///
/// **Desactivado por defecto** (`_kEnabled = false`) hasta el go-live del cobro,
/// igual que en el POS. Mientras esté desactivado, es un passthrough total.
class BillingGuard extends ConsumerWidget {
  const BillingGuard({super.key, required this.child});

  final Widget child;

  /// Interruptor global. Poner en `true` cuando se decida activar el bloqueo.
  static const bool _kEnabled = false;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!_kEnabled) return child;

    final businessId = ref.watch(authGateViewModelProvider).profile?.businessId;
    if (businessId == null) return child;

    final dataAsync = ref.watch(_guardDataProvider(businessId));
    return dataAsync.when(
      loading: () => const _GuardLoading(),
      error: (_, _) => child, // fail-open: nunca dejar al dueño fuera por un error
      data: (data) {
        final state = data.state;
        if (state == null) return child;

        if (state.isSuspended) {
          return _BillingBlockOverlay(
            businessId: businessId,
            icon: Icons.lock_outline_rounded,
            accent: MangoThemeFactory.danger,
            title: 'Suscripción suspendida',
            message: 'Tu suscripción está suspendida por falta de pago. '
                'Actualiza tu tarjeta para reactivar el servicio.',
            intent: CardIntent.replaceCard,
            actionLabel: 'Actualizar tarjeta',
          );
        }

        if (state.isTrial && !(data.card?.isVerified ?? false)) {
          return _BillingBlockOverlay(
            businessId: businessId,
            icon: Icons.credit_card_rounded,
            accent: MangoThemeFactory.mango,
            title: 'Registra tu tarjeta',
            message: 'Para seguir usando MangoPOS al terminar tu período de prueba, '
                'registra una tarjeta. El cobro es mensual y puedes cambiarla cuando quieras.',
            intent: CardIntent.tokenizeAndVerify,
            actionLabel: 'Agregar tarjeta',
          );
        }

        return child;
      },
    );
  }
}

class _GuardLoading extends StatelessWidget {
  const _GuardLoading();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}

class _BillingBlockOverlay extends ConsumerWidget {
  const _BillingBlockOverlay({
    required this.businessId,
    required this.icon,
    required this.accent,
    required this.title,
    required this.message,
    required this.intent,
    required this.actionLabel,
  });

  final String businessId;
  final IconData icon;
  final Color accent;
  final String title;
  final String message;
  final CardIntent intent;
  final String actionLabel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dpi = DpiScale.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: EdgeInsets.all(dpi.space(24)),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  BillingIconBadge(icon: icon, color: accent),
                  SizedBox(height: dpi.space(16)),
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: Theme.of(context)
                        .textTheme
                        .titleLarge
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  SizedBox(height: dpi.space(10)),
                  Text(
                    message,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: dpi.font(14),
                      height: 1.4,
                      color: MangoThemeFactory.mutedText(context),
                    ),
                  ),
                  SizedBox(height: dpi.space(24)),
                  AzulPaymentPageLauncher(
                    businessId: businessId,
                    intent: intent,
                    label: actionLabel,
                  ),
                  SizedBox(height: dpi.space(10)),
                  OutlinedButton(
                    onPressed: () => ref.invalidate(_guardDataProvider(businessId)),
                    style: OutlinedButton.styleFrom(
                      minimumSize: Size(double.infinity, dpi.scale(46)),
                    ),
                    child: const Text('Ya registré mi tarjeta'),
                  ),
                  SizedBox(height: dpi.space(10)),
                  TextButton(
                    onPressed: () => ref.read(authGateViewModelProvider.notifier).signOut(),
                    child: const Text('Cerrar sesión'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
