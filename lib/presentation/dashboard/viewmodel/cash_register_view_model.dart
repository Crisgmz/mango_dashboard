import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/di/providers.dart';
import '../../../domain/dashboard/dashboard_models.dart';

/// Desenlace de registrar un movimiento manual de caja desde el dashboard.
/// [needsApproval] no es un error: el RPC pide firma de supervisor para esa
/// razón o ese monto, y la UI tiene que preguntarlo antes de reintentar.
enum CashMovementStatus { ok, needsApproval, failed }

class CashMovementResult {
  const CashMovementResult(this.status, [this.error]);

  final CashMovementStatus status;
  final String? error;

  bool get isOk => status == CashMovementStatus.ok;
  bool get needsApproval => status == CashMovementStatus.needsApproval;
}

class CashRegisterState {
  const CashRegisterState({
    this.isLoading = false,
    this.summary,
    this.error,
  });

  final bool isLoading;
  final CashRegisterSummary? summary;
  final String? error;

  CashRegisterState copyWith({
    bool? isLoading,
    CashRegisterSummary? summary,
    String? error,
    bool clearError = false,
  }) {
    return CashRegisterState(
      isLoading: isLoading ?? this.isLoading,
      summary: summary ?? this.summary,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

class CashRegisterViewModel extends StateNotifier<CashRegisterState> {
  CashRegisterViewModel(this._ref) : super(const CashRegisterState());

  final Ref _ref;
  String? _businessId;

  void reset() {
    state = const CashRegisterState();
  }

  /// Owner force-closes an open session, then reloads. Returns null on success,
  /// or a user-facing error message. See [CashRegisterDataService.forceCloseSession].
  Future<String?> forceClose({
    required String sessionId,
    required String reason,
    double? endAmount,
  }) async {
    try {
      await _ref.read(cashRegisterDataServiceProvider).forceCloseSession(
            sessionId: sessionId,
            reason: reason,
            endAmount: endAmount,
          );
      final bid = _businessId;
      if (bid != null) await load(bid);
      return null;
    } catch (e) {
      final msg = e.toString();
      if (msg.contains('INSUFFICIENT_ROLE') || msg.contains('CLOSE_DENIED')) {
        return 'No tienes permiso para forzar el cierre de esta caja.';
      }
      if (msg.contains('CALLER_REQUIRED')) {
        return 'No se pudo identificar tu usuario. Vuelve a iniciar sesión.';
      }
      return 'No se pudo forzar el cierre. Intenta de nuevo.';
    }
  }

  /// Registra un movimiento manual en una caja ABIERTA (hoy la UI solo crea
  /// ingresos, `deposit`). Devuelve el desenlace ya traducido para la UI y
  /// recarga el resumen de cajas para que el nuevo monto se vea al instante.
  Future<CashMovementResult> registerMovement({
    required String sessionId,
    required String type,
    required double amount,
    required String reasonCode,
    String? description,
    bool approveAsSupervisor = false,
    String? businessId,
  }) async {
    try {
      await _ref.read(cashRegisterDataServiceProvider).createCashMovement(
            sessionId: sessionId,
            type: type,
            amount: amount,
            reasonCode: reasonCode,
            description: description,
            approveAsSupervisor: approveAsSupervisor,
          );
      final bid = businessId ?? _businessId;
      if (bid != null) await load(bid);
      return const CashMovementResult(CashMovementStatus.ok);
    } catch (e) {
      final msg = e.toString();
      if (msg.contains('APPROVAL_REQUIRED')) {
        return const CashMovementResult(CashMovementStatus.needsApproval);
      }
      return CashMovementResult(CashMovementStatus.failed, _movementError(msg));
    }
  }

  /// Traduce los códigos que levanta `fn_cash_transaction_create`.
  String _movementError(String msg) {
    if (msg.contains('SESSION_NOT_OPEN') || msg.contains('SESSION_NOT_FOUND')) {
      return 'Esa caja ya no está abierta. Vuelve a abrir el diálogo y elige otra.';
    }
    if (msg.contains('AMOUNT_MUST_BE_POSITIVE')) {
      return 'El monto debe ser mayor que cero.';
    }
    if (msg.contains('REASON_NOT_FOUND') ||
        msg.contains('REASON_WRONG_TYPE') ||
        msg.contains('REASON_REQUIRED')) {
      return 'La razón elegida ya no es válida para este negocio.';
    }
    if (msg.contains('PGRST202') ||
        msg.contains('Could not find the function') ||
        msg.contains('does not exist')) {
      return 'Este backend no tiene el módulo pro de caja instalado, así que '
          'no se pueden registrar movimientos desde el dashboard.';
    }
    return 'No se pudo registrar el movimiento. Intenta de nuevo.';
  }

  Future<void> load(String businessId) async {
    _businessId = businessId;
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final summary = await _ref
          .read(cashRegisterDataServiceProvider)
          .loadSummary(businessId);
      state = CashRegisterState(summary: summary);
    } catch (e) {
      // If we already have a cached summary, fail silently — show stale data
      // instead of blanking the page with a "sin conexión" error on every blip.
      if (state.summary != null) {
        state = state.copyWith(isLoading: false);
        return;
      }
      final msg = e.toString().toLowerCase();
      final isNetwork = msg.contains('socketexception') ||
          msg.contains('failed host lookup') ||
          msg.contains('network is unreachable') ||
          msg.contains('connection refused') ||
          msg.contains('connection closed');
      state = CashRegisterState(
        error: isNetwork
            ? 'Sin conexión a internet.'
            : 'No se pudo cargar las cajas. Intenta de nuevo.',
      );
    }
  }
}

final cashRegisterViewModelProvider =
    StateNotifierProvider<CashRegisterViewModel, CashRegisterState>(
  (ref) => CashRegisterViewModel(ref),
);
