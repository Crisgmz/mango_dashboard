import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/responsive/dpi_scale.dart';
import '../../auth/viewmodel/auth_gate_view_model.dart';
import '../../theme/theme_data_factory.dart';
import '../viewmodel/billing_view_model.dart';
import '../widgets/billing_ui.dart';
import '../widgets/charge_history_list.dart';
import '../widgets/pay_now_button.dart';
import '../widgets/payment_method_card.dart';
import '../widgets/subscription_status_card.dart';

/// Pantalla de suscripción del dueño: estado del plan, método de pago e
/// historial de cobros. Lee del Supabase compartido con el POS.
class BillingView extends ConsumerStatefulWidget {
  const BillingView({super.key});

  @override
  ConsumerState<BillingView> createState() => _BillingViewState();
}

class _BillingViewState extends ConsumerState<BillingView>
    with WidgetsBindingObserver {
  String? get _businessId =>
      ref.read(authGateViewModelProvider).profile?.businessId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final id = _businessId;
      if (id != null) ref.read(billingViewModelProvider.notifier).load(id);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      final id = _businessId;
      if (id == null) return;
      // Al volver de la Payment Page, comprueba si la tarjeta quedó registrada.
      ref.read(billingViewModelProvider.notifier).checkForNewCard(id);
    }
  }

  Future<void> _refresh() async {
    final id = _businessId;
    if (id != null) {
      await ref.read(billingViewModelProvider.notifier).refresh(id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final id = _businessId;
    final vm = ref.watch(billingViewModelProvider);

    // Snackbar cuando la tarjeta se registra con éxito.
    ref.listen<BillingScreenState>(billingViewModelProvider, (prev, next) {
      if (prev?.cardFlow != BillingCardFlow.success &&
          next.cardFlow == BillingCardFlow.success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Tarjeta registrada correctamente.')),
        );
      }
    });

    return Scaffold(
      appBar: AppBar(title: const Text('Suscripción')),
      body: id == null
          ? _centered(
              context,
              'No hay un negocio activo. Inicia sesión de nuevo.',
            )
          : RefreshIndicator(
              onRefresh: _refresh,
              child: _buildBody(context, vm, id),
            ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    BillingScreenState vm,
    String businessId,
  ) {
    if (vm.isLoading && !vm.hasData) {
      return const Center(child: CircularProgressIndicator());
    }
    if (vm.error != null && !vm.hasData) {
      return _errorState(context, vm.error!, businessId);
    }

    final dpi = DpiScale.of(context);
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.fromLTRB(
        dpi.space(16),
        dpi.space(16),
        dpi.space(16),
        dpi.space(32),
      ),
      children: [
        _cardFlowBanner(context, vm, businessId),
        SubscriptionStatusCard(state: vm.state),
        if (vm.hasVerifiedCard && vm.state?.canAttemptCharge == true) ...[
          SizedBox(height: dpi.space(14)),
          PayNowButton(businessId: businessId, state: vm.state!),
        ],
        SizedBox(height: dpi.space(14)),
        PaymentMethodCard(businessId: businessId, method: vm.paymentMethod),
        SizedBox(height: dpi.space(14)),
        ChargeHistoryList(charges: vm.charges),
      ],
    );
  }

  Widget _cardFlowBanner(
    BuildContext context,
    BillingScreenState vm,
    String businessId,
  ) {
    final dpi = DpiScale.of(context);
    final notifier = ref.read(billingViewModelProvider.notifier);

    Widget wrap(Widget child) => Padding(
      padding: EdgeInsets.only(bottom: dpi.space(14)),
      child: child,
    );

    if (vm.cardFlowError != null) {
      return wrap(
        BillingNotice(
          color: MangoThemeFactory.danger,
          icon: Icons.error_outline_rounded,
          message: vm.cardFlowError!,
        ),
      );
    }

    switch (vm.cardFlow) {
      case BillingCardFlow.awaiting:
        return wrap(
          Column(
            children: [
              BillingNotice(
                color: MangoThemeFactory.info,
                icon: Icons.open_in_browser_rounded,
                message:
                    'Completa el registro de tu tarjeta en la página de Azul. '
                    'Cuando termines, vuelve aquí y toca "Ya registré mi tarjeta".',
              ),
              SizedBox(height: dpi.space(10)),
              Row(
                children: [
                  Expanded(
                    child: FilledButton(
                      onPressed: () => notifier.checkForNewCard(businessId),
                      style: FilledButton.styleFrom(
                        backgroundColor: MangoThemeFactory.mango,
                        foregroundColor: Colors.white,
                      ),
                      child: const Text('Ya registré mi tarjeta'),
                    ),
                  ),
                  SizedBox(width: dpi.space(10)),
                  TextButton(
                    onPressed: notifier.dismissCardFlow,
                    child: const Text('Cancelar'),
                  ),
                ],
              ),
            ],
          ),
        );
      case BillingCardFlow.verifying:
        return wrap(
          BillingNotice(
            color: MangoThemeFactory.info,
            icon: Icons.hourglass_top_rounded,
            message: 'Verificando el registro de tu tarjeta…',
          ),
        );
      case BillingCardFlow.success:
        return wrap(
          Row(
            children: [
              Expanded(
                child: BillingNotice(
                  color: MangoThemeFactory.success,
                  icon: Icons.check_circle_outline_rounded,
                  message: 'Tu tarjeta quedó registrada y verificada.',
                ),
              ),
              SizedBox(width: dpi.space(8)),
              TextButton(
                onPressed: notifier.dismissCardFlow,
                child: const Text('Listo'),
              ),
            ],
          ),
        );
      case BillingCardFlow.idle:
      case BillingCardFlow.launching:
        return const SizedBox.shrink();
    }
  }

  Widget _errorState(BuildContext context, String message, String businessId) {
    final dpi = DpiScale.of(context);
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.all(dpi.space(24)),
      children: [
        SizedBox(height: dpi.space(80)),
        Icon(
          Icons.cloud_off_rounded,
          size: dpi.icon(48),
          color: MangoThemeFactory.mutedText(context),
        ),
        SizedBox(height: dpi.space(16)),
        Text(
          message,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: dpi.font(14),
            color: MangoThemeFactory.mutedText(context),
          ),
        ),
        SizedBox(height: dpi.space(20)),
        Center(
          child: FilledButton(
            onPressed: () =>
                ref.read(billingViewModelProvider.notifier).load(businessId),
            style: FilledButton.styleFrom(
              backgroundColor: MangoThemeFactory.mango,
              foregroundColor: Colors.white,
            ),
            child: const Text('Reintentar'),
          ),
        ),
      ],
    );
  }

  Widget _centered(BuildContext context, String message) {
    final dpi = DpiScale.of(context);
    return Center(
      child: Padding(
        padding: EdgeInsets.all(dpi.space(24)),
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: dpi.font(14),
            color: MangoThemeFactory.mutedText(context),
          ),
        ),
      ),
    );
  }
}
