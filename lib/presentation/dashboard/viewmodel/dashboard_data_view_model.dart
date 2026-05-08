import 'package:flutter/material.dart';
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
    this.cachedAt,
    this.isFromCache = false,
  });

  const DashboardDataState.initial()
    : isLoading = false,
      isRefreshing = false,
      summary = null,
      error = null,
      cachedAt = null,
      isFromCache = false;

  final bool isLoading;
  final bool isRefreshing;
  final DashboardSummary? summary;
  final String? error;

  /// Timestamp of the data currently displayed (from cache or fresh fetch).
  final DateTime? cachedAt;

  /// True when [summary] was loaded from the per-account cache (so the UI
  /// can show a "actualizando…" hint instead of a skeleton on switch).
  final bool isFromCache;

  DashboardDataState copyWith({
    bool? isLoading,
    bool? isRefreshing,
    DashboardSummary? summary,
    String? error,
    DateTime? cachedAt,
    bool? isFromCache,
    bool clearError = false,
  }) {
    return DashboardDataState(
      isLoading: isLoading ?? this.isLoading,
      isRefreshing: isRefreshing ?? this.isRefreshing,
      summary: summary ?? this.summary,
      error: clearError ? null : (error ?? this.error),
      cachedAt: cachedAt ?? this.cachedAt,
      isFromCache: isFromCache ?? this.isFromCache,
    );
  }
}

class DashboardDataViewModel extends StateNotifier<DashboardDataState> {
  DashboardDataViewModel(this._ref, {this.liteMode = false}) : super(const DashboardDataState.initial());

  final Ref _ref;
  final bool liteMode;
  int _retryCount = 0;
  static const _maxRetries = 3;

  String get _scope => liteMode ? 'sales' : 'home';
  String _cacheKey(String email) => '$email:$_scope';

  /// Limpia el estado para forzar skeleton.
  /// Nota: en cambio de cuenta normalmente NO conviene llamar a esto — usa
  /// [hydrateFromCache] para mostrar la última snapshot al instante.
  void reset() {
    _retryCount = 0;
    state = const DashboardDataState.initial();
  }

  /// Pulls a previously stored snapshot for [profile] from the cache and sets
  /// it as the current state, so the UI shows data instantly while a fresh
  /// fetch happens. Returns true if a cache hit was applied.
  bool hydrateFromCache(AdminAccessProfile profile) {
    final email = profile.email ?? '';
    if (email.isEmpty) return false;
    final cache = _ref.read(dashboardSummaryCacheProvider);
    final cached = cache.get(_cacheKey(email));
    if (cached == null) return false;
    state = DashboardDataState(
      isLoading: false,
      isRefreshing: false,
      summary: cached,
      error: null,
      cachedAt: cache.cachedAt(_cacheKey(email)),
      isFromCache: true,
    );
    return true;
  }

  Future<void> load(AdminAccessProfile profile, {required SalesDateFilter filter, DateTimeRange? customRange}) async {
    final currentlyHasData = state.summary != null;
    final isSwitchingAccount = currentlyHasData && state.summary?.profile.email != profile.email;

    // If switching account, try cache hydration first so the UI doesn't blank.
    if (isSwitchingAccount) {
      hydrateFromCache(profile);
    }

    final hasDataNow = state.summary != null;
    if (hasDataNow) {
      state = state.copyWith(isRefreshing: true, clearError: false);
    } else {
      state = state.copyWith(isLoading: true, clearError: true);
    }

    try {
      final summary = await _ref.read(dashboardDataServiceProvider).loadSummary(
        profile,
        filter: filter,
        customRange: customRange,
        liteMode: liteMode,
      );
      _retryCount = 0;

      // Cache the fresh snapshot for instant restore on the next account switch.
      final email = profile.email ?? '';
      if (email.isNotEmpty) {
        _ref.read(dashboardSummaryCacheProvider).put(_cacheKey(email), summary);
      }

      state = state.copyWith(
        isLoading: false,
        isRefreshing: false,
        summary: summary,
        cachedAt: DateTime.now(),
        isFromCache: false,
        clearError: true,
      );
    } catch (e) {
      if (_retryCount < _maxRetries && !isSwitchingAccount) {
        _retryCount++;
        await Future.delayed(Duration(seconds: _retryCount * 2));
        if (mounted) return load(profile, filter: filter, customRange: customRange);
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
  (ref) => DashboardDataViewModel(ref, liteMode: true),
);
