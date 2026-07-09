import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/billing/billing_charge.dart';
import '../../domain/billing/billing_enums.dart';
import '../../domain/billing/billing_payment_method.dart';
import '../../domain/billing/billing_state.dart';
import '../../domain/billing/tokenization_session.dart';

/// Acceso a los datos de suscripción/cobro del comercio.
///
/// Todo vive en el Supabase compartido con el POS (`mangospos`). El dashboard
/// solo **lee** (vistas públicas + fila ancla de `memberships`) e **invoca** la
/// Edge Function de tokenización. No muta ninguna columna del motor de cobro.
class BillingDataService {
  BillingDataService(this._client);

  final SupabaseClient _client;

  /// Estado de suscripción de la fila ancla (`is_billing_anchor = true`).
  /// Une el plan (`plans`) y los últimos cargos OK/fallido vía la vista pública.
  /// Devuelve null si el comercio aún no tiene fila de billing.
  Future<BillingState?> getBillingState(String businessId) async {
    final row = await _client
        .from('memberships')
        .select('''
          id,
          business_id,
          plan_id,
          is_billing_anchor,
          billing_status,
          trial_ends_at,
          current_period_start,
          current_period_end,
          next_billing_date,
          consent_granted_at,
          current_attempt_number,
          suspended_at,
          cancelled_at,
          cancellation_reason,
          plan:plans(*),
          last_successful_charge:azul_charges_public!last_successful_charge_id(*),
          last_failed_charge:azul_charges_public!last_failed_charge_id(*)
        ''')
        .eq('business_id', businessId)
        .eq('is_billing_anchor', true)
        .maybeSingle();
    if (row == null) return null;
    return BillingState.fromJson(row);
  }

  /// Tarjeta default verificada del comercio (sin exponer el token).
  Future<BillingPaymentMethod?> getDefaultPaymentMethod(
    String businessId,
  ) async {
    final row = await _client
        .from('azul_payment_methods_public')
        .select()
        .eq('business_id', businessId)
        .eq('is_default', true)
        .maybeSingle();
    if (row == null) return null;
    return BillingPaymentMethod.fromJson(row);
  }

  /// Todas las tarjetas no revocadas del comercio (default primero).
  Future<List<BillingPaymentMethod>> listPaymentMethods(
    String businessId,
  ) async {
    final rows = await _client
        .from('azul_payment_methods_public')
        .select()
        .eq('business_id', businessId)
        .isFilter('revoked_at', null)
        .order('is_default', ascending: false)
        .order('created_at', ascending: false);
    return List<Map<String, dynamic>>.from(
      rows,
    ).map(BillingPaymentMethod.fromJson).toList(growable: false);
  }

  /// Historial de cobros mensuales (más reciente primero).
  Future<List<BillingCharge>> listCharges(
    String businessId, {
    int limit = 60,
  }) async {
    final rows = await _client
        .from('azul_charges_public')
        .select()
        .eq('business_id', businessId)
        .order('attempted_at', ascending: false)
        .limit(limit);
    return List<Map<String, dynamic>>.from(
      rows,
    ).map(BillingCharge.fromJson).toList(growable: false);
  }

  /// Crea una sesión de la Azul Payment Page para registrar/cambiar tarjeta.
  /// Invoca la Edge Function `azul-create-tokenization-session` (valida que el
  /// usuario sea owner/admin del negocio). Devuelve la URL a abrir.
  Future<TokenizationSession> createTokenizationSession({
    required String businessId,
    CardIntent intent = CardIntent.tokenizeAndVerify,
  }) async {
    final response = await _client.functions.invoke(
      'azul-create-tokenization-session',
      body: {
        'business_id': businessId,
        'intent_type': intent.raw,
        'client_surface': 'flutter_app',
      },
    );

    final data = response.data;
    if (data is! Map) {
      throw const BillingException(
        'Respuesta inesperada del servidor al crear la sesión de pago.',
      );
    }
    final map = Map<String, dynamic>.from(data);
    final session = TokenizationSession.fromJson(map);
    if (session.paymentPageUrl.isEmpty) {
      throw const BillingException(
        'El servidor no devolvió la página de pago. Intenta de nuevo.',
      );
    }
    return session;
  }

  /// Cobra la suscripción AHORA ("Pagar ahora") con la tarjeta default, vía la
  /// Edge Function `azul-charge-now` (autoriza al owner/admin y delega en
  /// `azul-charge-subscription` con service_role; gate de 48 h server-side).
  ///
  /// No lanza por tarjeta declinada (HTTP 200, `ok:false`) — eso viene en el
  /// [ChargeNowResult]. Lanza [BillingException] en errores reales (sin tarjeta,
  /// suspendido, fuera de la ventana de 48 h, red, etc.).
  Future<ChargeNowResult> chargeNow({required String businessId}) async {
    final dynamic data;
    try {
      final response = await _client.functions.invoke(
        'azul-charge-now',
        body: {'business_id': businessId},
      );
      data = response.data;
    } on FunctionException catch (e) {
      throw BillingException(_chargeErrorMessage(e.details));
    }

    if (data is! Map) {
      throw const BillingException(
        'Respuesta inesperada del servidor al procesar el cobro.',
      );
    }
    final map = Map<String, dynamic>.from(data);
    if (map.containsKey('error')) {
      throw BillingException(_chargeErrorMessage(map));
    }
    return ChargeNowResult(
      approved: map['ok'] == true,
      status: map['status']?.toString() ?? '',
      responseMessage: map['response_message']?.toString(),
      idempotent: map['idempotent'] == true,
    );
  }

  String _chargeErrorMessage(dynamic details) {
    if (details is Map) {
      final err = details['error'];
      if (err is Map && err['message'] != null) {
        return err['message'].toString();
      }
      final m = details['response_message'] ?? details['message'];
      if (m != null) return m.toString();
    }
    return 'No se pudo procesar el cobro. Intenta de nuevo.';
  }
}

/// Resultado de un cobro manual de la suscripción ([BillingDataService.chargeNow]).
class ChargeNowResult {
  const ChargeNowResult({
    required this.approved,
    required this.status,
    required this.responseMessage,
    required this.idempotent,
  });

  /// `true` si Azul aprobó (IsoCode 00).
  final bool approved;

  /// Estado de la charge: 'approved' | 'declined' | 'error'.
  final String status;
  final String? responseMessage;

  /// `true` si el período ya estaba cobrado y se devolvió sin recobrar.
  final bool idempotent;
}

/// Error de dominio del módulo de billing, con mensaje apto para mostrar al usuario.
class BillingException implements Exception {
  const BillingException(this.message);
  final String message;

  @override
  String toString() => message;
}
