import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/di/providers.dart';
import '../../../domain/inventory/inventory_models.dart';

/// Contadores del hub de Inventario (PRD 6.2 A.1/A.2). Cada grupo se carga en
/// paralelo e independiente: si uno falla, su fila se muestra sin contador —
/// nunca bloquea al resto. Rotación (90 días) queda oculta hasta tener la
/// fuente de costo de venta (regla A.1: oculto sin datos suficientes).
class InventoryHubState {
  const InventoryHubState({
    this.stockValue,
    this.itemCount,
    this.lowCount,
    this.onOrderValue,
    this.openPoCount,
    this.receivedTodayCount,
    this.lastCountAt,
    this.lastCountStatus,
    this.activeSuppliers,
    this.suggestionsCount,
    this.pendingTransfers,
  });

  /// Σ stock × costo promedio (valor a costo, sucursal activa).
  final double? stockValue;
  final int? itemCount;

  /// Artículos bajo mínimo (conteo de artículos, no unidades).
  final int? lowCount;

  /// Valor RD$ pendiente en POs enviadas/parciales. 0 se muestra como RD$0.
  final double? onOrderValue;
  final int? openPoCount;
  final int? receivedTodayCount;
  final DateTime? lastCountAt;
  final String? lastCountStatus;
  final int? activeSuppliers;

  /// Sugerencias de "Qué comprar hoy" (artículos bajo punto de reorden).
  final int? suggestionsCount;

  /// Transferencias por aprobar o en tránsito.
  final int? pendingTransfers;

  InventoryHubState copyWith({
    double? stockValue,
    int? itemCount,
    int? lowCount,
    double? onOrderValue,
    int? openPoCount,
    int? receivedTodayCount,
    DateTime? lastCountAt,
    String? lastCountStatus,
    int? activeSuppliers,
    int? suggestionsCount,
    int? pendingTransfers,
  }) {
    return InventoryHubState(
      stockValue: stockValue ?? this.stockValue,
      itemCount: itemCount ?? this.itemCount,
      lowCount: lowCount ?? this.lowCount,
      onOrderValue: onOrderValue ?? this.onOrderValue,
      openPoCount: openPoCount ?? this.openPoCount,
      receivedTodayCount: receivedTodayCount ?? this.receivedTodayCount,
      lastCountAt: lastCountAt ?? this.lastCountAt,
      lastCountStatus: lastCountStatus ?? this.lastCountStatus,
      activeSuppliers: activeSuppliers ?? this.activeSuppliers,
      suggestionsCount: suggestionsCount ?? this.suggestionsCount,
      pendingTransfers: pendingTransfers ?? this.pendingTransfers,
    );
  }
}

class InventoryHubViewModel extends StateNotifier<InventoryHubState> {
  InventoryHubViewModel(this._ref) : super(const InventoryHubState());

  final Ref _ref;

  Future<void> load(String businessId) async {
    // Cuatro grupos independientes: el que falla deja sus campos como están.
    await Future.wait([
      _loadStock(businessId),
      _loadPurchasing(businessId),
      _loadCounts(businessId),
      _loadSuppliers(businessId),
      _loadSuggestions(businessId),
      _loadTransfers(businessId),
    ]);
  }

  Future<void> _loadStock(String businessId) async {
    try {
      final items = await _ref
          .read(inventoryDataServiceProvider)
          .loadInventory(businessId);
      var value = 0.0;
      var low = 0;
      for (final InventoryItemSnapshot i in items) {
        if (i.cost != null && i.totalQuantity > 0) {
          value += i.totalQuantity * i.cost!;
        }
        if (i.isLow || i.isOut) low++;
      }
      if (!mounted) return;
      state = state.copyWith(
        stockValue: value,
        itemCount: items.length,
        lowCount: low,
      );
    } catch (_) {/* fila sin contador */}
  }

  Future<void> _loadPurchasing(String businessId) async {
    try {
      final orders = await _ref
          .read(purchasingDataServiceProvider)
          .loadPurchaseOrders(businessId);
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final open = orders.where((o) => o.isOpen).length;
      final receivedToday = orders
          .where((o) =>
              o.receivedDate != null &&
              !o.receivedDate!.isBefore(today) &&
              o.receivedDate!.isBefore(today.add(const Duration(days: 1))))
          .length;
      // Valor en orden: total de las POs abiertas ya enviadas (no borradores).
      final onOrderValue = orders
          .where((o) => o.status == 'sent' || o.status == 'partial')
          .fold<double>(0, (sum, o) => sum + o.total);
      if (!mounted) return;
      state = state.copyWith(
        openPoCount: open,
        receivedTodayCount: receivedToday,
        onOrderValue: onOrderValue,
      );
    } catch (_) {/* fila sin contador */}
  }

  Future<void> _loadCounts(String businessId) async {
    try {
      final sessions = await _ref
          .read(physicalCountServiceProvider)
          .loadSessions(businessId);
      if (sessions.isEmpty || !mounted) return;
      final last = sessions.first;
      state = state.copyWith(
        lastCountAt: last.startedAt,
        lastCountStatus: last.status,
      );
    } catch (_) {/* fila sin contador */}
  }

  Future<void> _loadSuppliers(String businessId) async {
    try {
      final suppliers = await _ref
          .read(purchasingDataServiceProvider)
          .loadSuppliers(businessId);
      if (!mounted) return;
      state = state.copyWith(
        activeSuppliers: suppliers.where((s) => s.isActive).length,
      );
    } catch (_) {/* fila sin contador */}
  }

  Future<void> _loadSuggestions(String businessId) async {
    try {
      final suggestions = await _ref
          .read(purchasingDataServiceProvider)
          .loadReorderSuggestions(businessId);
      if (!mounted) return;
      state = state.copyWith(suggestionsCount: suggestions.length);
    } catch (_) {/* fila sin contador */}
  }

  Future<void> _loadTransfers(String businessId) async {
    try {
      final transfers = await _ref
          .read(stockTransferServiceProvider)
          .loadTransfers(businessId);
      if (!mounted) return;
      state = state.copyWith(
        pendingTransfers: transfers
            .where((t) => t.isPendingApproval || t.isInTransit)
            .length,
      );
    } catch (_) {/* fila sin contador */}
  }
}

final inventoryHubViewModelProvider =
    StateNotifierProvider<InventoryHubViewModel, InventoryHubState>(
  (ref) => InventoryHubViewModel(ref),
);
