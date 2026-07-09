import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/di/providers.dart';

class NotificationSettingsState {
  const NotificationSettingsState({
    this.loading = true,
    this.disabledByBusiness = const {},
    this.error,
  });

  final bool loading;

  /// businessId -> set of DISABLED event keys (opt-out: absent = enabled).
  final Map<String, Set<String>> disabledByBusiness;
  final String? error;

  bool isEnabled(String businessId, String eventKey) =>
      !(disabledByBusiness[businessId]?.contains(eventKey) ?? false);

  NotificationSettingsState copyWith({
    bool? loading,
    Map<String, Set<String>>? disabledByBusiness,
    String? error,
    bool clearError = false,
  }) {
    return NotificationSettingsState(
      loading: loading ?? this.loading,
      disabledByBusiness: disabledByBusiness ?? this.disabledByBusiness,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

class NotificationSettingsViewModel
    extends StateNotifier<NotificationSettingsState> {
  NotificationSettingsViewModel(this._ref)
      : super(const NotificationSettingsState()) {
    _load();
  }

  final Ref _ref;

  Future<void> _load() async {
    try {
      final disabled =
          await _ref.read(notificationPreferencesServiceProvider).loadDisabled();
      state = state.copyWith(
        loading: false,
        disabledByBusiness: disabled,
        clearError: true,
      );
    } catch (_) {
      state = state.copyWith(
        loading: false,
        error: 'No se pudieron cargar las preferencias.',
      );
    }
  }

  Future<void> refresh() => _load();

  /// Toggles one event for one business. Optimistic with revert on failure.
  Future<void> toggle({
    required String businessId,
    required String eventKey,
    required bool enabled,
  }) async {
    state = state.copyWith(
      disabledByBusiness: _withChange(businessId, eventKey, enabled),
      clearError: true,
    );
    try {
      await _ref.read(notificationPreferencesServiceProvider).setEnabled(
            businessId: businessId,
            eventType: eventKey,
            enabled: enabled,
          );
    } catch (_) {
      state = state.copyWith(
        disabledByBusiness: _withChange(businessId, eventKey, !enabled),
        error: 'No se pudo guardar el cambio. Intenta de nuevo.',
      );
    }
  }

  /// Returns a deep copy of the disabled map with one event flipped.
  Map<String, Set<String>> _withChange(
    String businessId,
    String eventKey,
    bool enabled,
  ) {
    final next = <String, Set<String>>{
      for (final entry in state.disabledByBusiness.entries)
        entry.key: {...entry.value},
    };
    final set = next.putIfAbsent(businessId, () => <String>{});
    if (enabled) {
      set.remove(eventKey);
    } else {
      set.add(eventKey);
    }
    return next;
  }
}

final notificationSettingsViewModelProvider = StateNotifierProvider.autoDispose<
    NotificationSettingsViewModel, NotificationSettingsState>(
  (ref) => NotificationSettingsViewModel(ref),
);
