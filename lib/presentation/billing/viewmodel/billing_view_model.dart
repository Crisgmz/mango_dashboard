import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/di/providers.dart';
import '../../../data/billing/billing_data_service.dart';
import '../../../domain/billing/billing_charge.dart';
import '../../../domain/billing/billing_enums.dart';
import '../../../domain/billing/billing_payment_method.dart';
import '../../../domain/billing/billing_state.dart';

/// Etapa del flujo de registro/cambio de tarjeta vía la Azul Payment Page.
enum BillingCardFlow {
  /// Sin flujo activo.
  idle,

  /// Creando la sesión y abriendo el navegador.
  launching,

  /// El navegador está abierto; esperando que el usuario regrese.
  awaiting,

  /// Verificando si la tarjeta quedó registrada al volver.
  verifying,

  /// Tarjeta registrada con éxito.
  success,
}

class BillingScreenState {
  const BillingScreenState({
    this.isLoading = false,
    this.state,
    this.paymentMethod,
    this.charges,
    this.error,
    this.cardFlow = BillingCardFlow.idle,
    this.cardFlowError,
  });

  /// Carga inicial en curso (no hay datos aún).
  final bool isLoading;

  /// Estado de suscripción (fila ancla). Null si el comercio no tiene billing.
  final BillingState? state;

  /// Tarjeta default verificada (o null si no hay).
  final BillingPaymentMethod? paymentMethod;

  /// Historial de cobros.
  final List<BillingCharge>? charges;

  /// Error de carga (apto para mostrar).
  final String? error;

  /// Etapa del flujo de tarjeta.
  final BillingCardFlow cardFlow;

  /// Error específico del flujo de tarjeta.
  final String? cardFlowError;

  bool get hasData => state != null || paymentMethod != null || (charges?.isNotEmpty ?? false);
  bool get hasVerifiedCard => paymentMethod?.isVerified ?? false;

  BillingScreenState copyWith({
    bool? isLoading,
    BillingState? state,
    BillingPaymentMethod? paymentMethod,
    List<BillingCharge>? charges,
    String? error,
    BillingCardFlow? cardFlow,
    String? cardFlowError,
    bool clearError = false,
    bool clearPaymentMethod = false,
    bool clearCardFlowError = false,
  }) {
    return BillingScreenState(
      isLoading: isLoading ?? this.isLoading,
      state: state ?? this.state,
      paymentMethod: clearPaymentMethod ? null : (paymentMethod ?? this.paymentMethod),
      charges: charges ?? this.charges,
      error: clearError ? null : (error ?? this.error),
      cardFlow: cardFlow ?? this.cardFlow,
      cardFlowError: clearCardFlowError ? null : (cardFlowError ?? this.cardFlowError),
    );
  }
}

class BillingViewModel extends StateNotifier<BillingScreenState> {
  BillingViewModel(this._ref) : super(const BillingScreenState());

  final Ref _ref;

  /// Id de la tarjeta default antes de abrir la Payment Page, para detectar
  /// cuándo aparece una nueva.
  String? _cardIdBeforeFlow;

  BillingDataService get _service => _ref.read(billingDataServiceProvider);

  /// Carga inicial (blanquea la pantalla con spinner si no hay datos).
  Future<void> load(String businessId) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final results = await _fetchAll(businessId);
      state = state.copyWith(
        isLoading: false,
        state: results.$1,
        paymentMethod: results.$2,
        clearPaymentMethod: results.$2 == null,
        charges: results.$3,
        clearError: true,
      );
    } catch (e) {
      state = state.copyWith(isLoading: false, error: _friendlyError(e));
    }
  }

  /// Recarga sin blanquear: mantiene los datos previos si algo falla.
  Future<void> refresh(String businessId) async {
    try {
      final results = await _fetchAll(businessId);
      state = state.copyWith(
        state: results.$1,
        paymentMethod: results.$2,
        clearPaymentMethod: results.$2 == null,
        charges: results.$3,
        clearError: true,
      );
    } catch (_) {
      // Silencioso: conserva los datos en pantalla ante un blip de red.
    }
  }

  Future<(BillingState?, BillingPaymentMethod?, List<BillingCharge>)> _fetchAll(
    String businessId,
  ) async {
    final results = await Future.wait([
      _service.getBillingState(businessId),
      _service.getDefaultPaymentMethod(businessId),
      _service.listCharges(businessId),
    ]);
    return (
      results[0] as BillingState?,
      results[1] as BillingPaymentMethod?,
      (results[2] as List<BillingCharge>?) ?? const <BillingCharge>[],
    );
  }

  /// Inicia el registro/cambio de tarjeta: crea la sesión y abre la Payment Page.
  Future<void> startCardRegistration(
    String businessId, {
    CardIntent intent = CardIntent.tokenizeAndVerify,
  }) async {
    _cardIdBeforeFlow = state.paymentMethod?.id;
    state = state.copyWith(cardFlow: BillingCardFlow.launching, clearCardFlowError: true);
    try {
      final session = await _service.createTokenizationSession(
        businessId: businessId,
        intent: intent,
      );
      final uri = Uri.parse(session.paymentPageUrl);
      final launched = await launchUrl(uri, mode: _launchMode());
      if (!launched) {
        throw const BillingException(
          'No se pudo abrir la página de pago. Verifica tu navegador.',
        );
      }
      state = state.copyWith(cardFlow: BillingCardFlow.awaiting);
    } catch (e) {
      state = state.copyWith(
        cardFlow: BillingCardFlow.idle,
        cardFlowError: _friendlyError(e),
      );
    }
  }

  /// Llamar cuando la app vuelve al frente o el usuario toca "Ya registré mi
  /// tarjeta": comprueba (con reintentos) si apareció una tarjeta verificada
  /// nueva. El backend (azul-callback) la inserta de forma asíncrona.
  Future<void> checkForNewCard(String businessId) async {
    if (state.cardFlow != BillingCardFlow.awaiting) return;
    state = state.copyWith(cardFlow: BillingCardFlow.verifying);

    const attempts = 5;
    for (var i = 0; i < attempts; i++) {
      try {
        final pm = await _service.getDefaultPaymentMethod(businessId);
        final isNew = pm != null &&
            pm.isVerified &&
            (pm.id != _cardIdBeforeFlow || _cardIdBeforeFlow == null);
        if (isNew) {
          await refresh(businessId);
          state = state.copyWith(cardFlow: BillingCardFlow.success);
          return;
        }
      } catch (_) {
        // Reintenta en la siguiente iteración.
      }
      if (i < attempts - 1) {
        await Future<void>.delayed(const Duration(milliseconds: 1500));
      }
    }

    // No apareció todavía: vuelve a "esperando" para que el usuario reintente.
    if (mounted) {
      state = state.copyWith(cardFlow: BillingCardFlow.awaiting);
    }
  }

  /// Cierra el estado del flujo de tarjeta (banners de éxito/espera).
  void dismissCardFlow() {
    _cardIdBeforeFlow = null;
    state = state.copyWith(cardFlow: BillingCardFlow.idle, clearCardFlowError: true);
  }

  /// `inAppBrowserView` en móvil (Custom Tabs / SafariVC, comparte sesión);
  /// navegador del sistema en web/escritorio. Igual criterio que el POS.
  LaunchMode _launchMode() {
    if (!kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS)) {
      return LaunchMode.inAppBrowserView;
    }
    return LaunchMode.externalApplication;
  }

  String _friendlyError(Object e) {
    if (e is BillingException) return e.message;
    final msg = e.toString().toLowerCase();
    if (msg.contains('socketexception') ||
        msg.contains('failed host lookup') ||
        msg.contains('network is unreachable') ||
        msg.contains('connection refused') ||
        msg.contains('connection closed')) {
      return 'Sin conexión a internet.';
    }
    if (msg.contains('forbidden') || msg.contains('403')) {
      return 'No tienes permiso para gestionar la suscripción de este negocio.';
    }
    return 'No se pudo completar la operación. Intenta de nuevo.';
  }
}

final billingViewModelProvider =
    StateNotifierProvider<BillingViewModel, BillingScreenState>(
  (ref) => BillingViewModel(ref),
);
