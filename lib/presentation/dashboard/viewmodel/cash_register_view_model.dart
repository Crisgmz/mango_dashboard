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
      state = CashRegisterState(error: 'No se pudo cargar las cajas: $e');
    }
  }
}

final cashRegisterViewModelProvider =
    StateNotifierProvider<CashRegisterViewModel, CashRegisterState>(
  (ref) => CashRegisterViewModel(ref),
);
