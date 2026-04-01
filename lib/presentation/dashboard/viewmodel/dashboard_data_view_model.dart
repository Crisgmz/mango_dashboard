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

  Future<void> load(AdminAccessProfile profile, {SalesDateFilter? filter}) async {
    final currentlyHasData = state.summary != null;
    
    if (currentlyHasData) {
      state = state.copyWith(isRefreshing: true, clearError: false);
    } else {
      state = state.copyWith(isLoading: true, clearError: true);
    }

    try {
      final summary = await _ref.read(dashboardDataServiceProvider).loadSummary(
        profile,
        filter: filter ?? state.summary?.filter ?? SalesDateFilter.month,
      );
      state = state.copyWith(isLoading: false, isRefreshing: false, summary: summary, error: null);
    } catch (e) {
      state = state.copyWith(isLoading: false, isRefreshing: false, error: 'No se pudo cargar el dashboard: $e');
    }
  }
}

final dashboardDataViewModelProvider = StateNotifierProvider<DashboardDataViewModel, DashboardDataState>(
  (ref) => DashboardDataViewModel(ref),
);
