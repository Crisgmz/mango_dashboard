import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/di/providers.dart';
import '../../../domain/auth/admin_access_profile.dart';
import '../../../domain/dashboard/dashboard_models.dart';

class DashboardDataState {
  const DashboardDataState({
    required this.isLoading,
    required this.isRefreshing,
    required this.summary,
    required this.error,
  });

  const DashboardDataState.initial()
    : isLoading = false,
      isRefreshing = false,
      summary = null,
      error = null;

  final bool isLoading;
  final bool isRefreshing;
  final DashboardSummary? summary;
  final String? error;

  DashboardDataState copyWith({
    bool? isLoading,
    bool? isRefreshing,
    DashboardSummary? summary,
    String? error,
    bool clearError = false,
  }) {
    return DashboardDataState(
      isLoading: isLoading ?? this.isLoading,
      isRefreshing: isRefreshing ?? this.isRefreshing,
      summary: summary ?? this.summary,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

class DashboardDataViewModel extends StateNotifier<DashboardDataState> {
  DashboardDataViewModel(this._ref) : super(const DashboardDataState.initial());

  final Ref _ref;
  int _retryCount = 0;
  static const _maxRetries = 3;

  /// Limpia el estado para forzar skeleton en cambio de negocio.
  void reset() {
    _retryCount = 0;
    state = const DashboardDataState.initial();
  }

  Future<void> load(AdminAccessProfile profile, {required SalesDateFilter filter}) async {
    final currentlyHasData = state.summary != null;

    if (currentlyHasData) {
      state = state.copyWith(isRefreshing: true, clearError: false);
    } else {
      state = state.copyWith(isLoading: true, clearError: true);
    }

    try {
      final summary = await _ref.read(dashboardDataServiceProvider).loadSummary(
        profile,
        filter: filter,
      );
      _retryCount = 0;
      state = state.copyWith(
        isLoading: false,
        isRefreshing: false,
        summary: summary,
        clearError: true,
      );
    } catch (e) {
      if (_retryCount < _maxRetries) {
        _retryCount++;
        await Future.delayed(Duration(seconds: _retryCount * 2));
        if (mounted) return load(profile, filter: filter);
        return;
      }
      _retryCount = 0;
      state = state.copyWith(
        isLoading: false,
        isRefreshing: false,
        error: _friendlyError(e),
      );
    }
  }

  static String _friendlyError(Object e) {
    final msg = e.toString();
    if (msg.contains('SocketException') || msg.contains('Failed host lookup') || msg.contains('Network is unreachable')) {
      return 'Sin conexión a internet. Verifica tu red e intenta de nuevo.';
    }
    if (msg.contains('TimeoutException') || msg.contains('timed out')) {
      return 'El servidor tardó demasiado en responder. Intenta de nuevo.';
    }
    if (msg.contains('HandshakeException') || msg.contains('CERTIFICATE')) {
      return 'Error de conexión segura. Verifica tu red.';
    }
    if (msg.contains('500') || msg.contains('502') || msg.contains('503')) {
      return 'El servidor no está disponible en este momento. Intenta más tarde.';
    }
    return 'Ocurrió un error inesperado. Intenta de nuevo.';
  }
}

final dashboardHomeDataViewModelProvider =
    StateNotifierProvider<DashboardDataViewModel, DashboardDataState>(
  (ref) => DashboardDataViewModel(ref),
);

final salesDataViewModelProvider =
    StateNotifierProvider<DashboardDataViewModel, DashboardDataState>(
  (ref) => DashboardDataViewModel(ref),
);
