import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../app/di/providers.dart';
import '../../../domain/inventory/inventory_models.dart';
import '../../auth/viewmodel/auth_gate_view_model.dart';

class InventoryState {
  const InventoryState({
    this.isLoading = false,
    this.items = const [],
    this.error,
  });

  final bool isLoading;
  final List<InventoryItemSnapshot> items;
  final String? error;

  InventoryState copyWith({
    bool? isLoading,
    List<InventoryItemSnapshot>? items,
    String? error,
    bool clearError = false,
  }) {
    return InventoryState(
      isLoading: isLoading ?? this.isLoading,
      items: items ?? this.items,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

class InventoryViewModel extends StateNotifier<InventoryState> {
  InventoryViewModel(this._ref) : super(const InventoryState());

  final Ref _ref;
  RealtimeChannel? _channel;
  Timer? _debounce;
  String? _subscribedBusinessId;

  Future<void> load() async {
    final profile = _ref.read(authGateViewModelProvider).profile;
    final businessId = profile?.businessId;
    if (businessId == null) {
      state = const InventoryState(error: 'No se pudo identificar el negocio.');
      return;
    }
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final items =
          await _ref.read(inventoryDataServiceProvider).loadInventory(businessId);
      state = state.copyWith(
        isLoading: false,
        items: items,
        clearError: true,
      );
      _ensureSubscription(businessId);
    } catch (e) {
      // Keep stale items visible if we already have them — same pattern used
      // elsewhere to avoid blanking on network blips.
      if (state.items.isNotEmpty) {
        state = state.copyWith(isLoading: false);
        return;
      }
      state = state.copyWith(
        isLoading: false,
        error: 'No se pudo cargar el inventario.',
      );
    }
  }

  void _ensureSubscription(String businessId) {
    if (_subscribedBusinessId == businessId && _channel != null) return;
    _unsubscribe();
    _subscribedBusinessId = businessId;
    _channel = _ref
        .read(inventoryDataServiceProvider)
        .subscribeStockChanges(
          channelTag: businessId,
          onChange: _scheduleReload,
        );
  }

  void _scheduleReload() {
    // Debounce: a single sale fires many stock updates in cascade
    // (one per ingredient consumed). Coalesce them into one refresh.
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
      if (!mounted) return;
      load();
    });
  }

  void _unsubscribe() {
    _channel?.unsubscribe();
    _channel = null;
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _unsubscribe();
    super.dispose();
  }
}

final inventoryViewModelProvider =
    StateNotifierProvider<InventoryViewModel, InventoryState>(
  (ref) => InventoryViewModel(ref),
);
