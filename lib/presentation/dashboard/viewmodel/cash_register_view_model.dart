import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/di/providers.dart';
import '../../../domain/dashboard/dashboard_models.dart';

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

  void reset() {
    state = const CashRegisterState();
  }

  Future<void> load(String businessId) async {
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
