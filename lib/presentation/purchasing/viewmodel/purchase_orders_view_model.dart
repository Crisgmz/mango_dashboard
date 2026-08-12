import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/di/providers.dart';
import '../../../domain/inventory/inventory_models.dart';
import '../../../domain/purchasing/purchase_order.dart';
import '../../../domain/purchasing/supplier.dart';

class PurchaseOrdersState {
  const PurchaseOrdersState({
    this.isLoading = false,
    this.orders = const [],
    this.suppliers = const [],
    this.warehouses = const [],
    this.error,
    this.saving = false,
  });

  final bool isLoading;
  final List<PurchaseOrder> orders;

  /// Suplidores activos para el selector del formulario.
  final List<Supplier> suppliers;
  final List<WarehouseInfo> warehouses;
  final String? error;
  final bool saving;

  PurchaseOrdersState copyWith({
    bool? isLoading,
    List<PurchaseOrder>? orders,
    List<Supplier>? suppliers,
    List<WarehouseInfo>? warehouses,
    String? error,
    bool? saving,
    bool clearError = false,
  }) {
    return PurchaseOrdersState(
      isLoading: isLoading ?? this.isLoading,
      orders: orders ?? this.orders,
      suppliers: suppliers ?? this.suppliers,
      warehouses: warehouses ?? this.warehouses,
      error: clearError ? null : (error ?? this.error),
      saving: saving ?? this.saving,
    );
  }
}

class PurchaseOrdersViewModel extends StateNotifier<PurchaseOrdersState> {
  PurchaseOrdersViewModel(this._ref) : super(const PurchaseOrdersState());

  final Ref _ref;

  Future<void> load(String businessId) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final service = _ref.read(purchasingDataServiceProvider);
      final results = await Future.wait([
        service.loadPurchaseOrders(businessId),
        service.loadSuppliers(businessId),
        service.loadWarehouses(businessId),
      ]);
      state = state.copyWith(
        isLoading: false,
        orders: results[0] as List<PurchaseOrder>,
        suppliers: (results[1] as List<Supplier>)
            .where((s) => s.isActive)
            .toList(growable: false),
        warehouses: results[2] as List<WarehouseInfo>,
        clearError: true,
      );
    } catch (e) {
      state = state.copyWith(isLoading: false, error: _friendly(e));
    }
  }

  Future<void> refresh(String businessId) async {
    try {
      final orders = await _ref
          .read(purchasingDataServiceProvider)
          .loadPurchaseOrders(businessId);
      state = state.copyWith(orders: orders, clearError: true);
    } catch (_) {/* conserva los datos en pantalla */}
  }

  /// Crea la OC. Devuelve el id creado o null si falló.
  Future<String?> create(
    String businessId, {
    required String supplierId,
    required String warehouseId,
    required String status,
    required DateTime expectedDate,
    String? notes,
    required List<PurchaseOrderLineDraft> lines,
  }) async {
    state = state.copyWith(saving: true, clearError: true);
    try {
      final id = await _ref.read(purchasingDataServiceProvider).createPurchaseOrder(
            businessId: businessId,
            supplierId: supplierId,
            warehouseId: warehouseId,
            status: status,
            expectedDate: expectedDate,
            notes: notes,
            lines: lines,
          );
      await refresh(businessId);
      state = state.copyWith(saving: false);
      return id;
    } catch (e) {
      state = state.copyWith(saving: false, error: _friendly(e));
      return null;
    }
  }

  Future<bool> markSent(String businessId, String orderId) async {
    state = state.copyWith(saving: true, clearError: true);
    try {
      await _ref.read(purchasingDataServiceProvider).markOrderSent(orderId);
      await refresh(businessId);
      state = state.copyWith(saving: false);
      return true;
    } catch (e) {
      state = state.copyWith(saving: false, error: _friendly(e));
      return false;
    }
  }

  Future<bool> cancel(String businessId, String orderId) async {
    state = state.copyWith(saving: true, clearError: true);
    try {
      await _ref.read(purchasingDataServiceProvider).cancelOrder(orderId);
      await refresh(businessId);
      state = state.copyWith(saving: false);
      return true;
    } catch (e) {
      state = state.copyWith(saving: false, error: _friendly(e));
      return false;
    }
  }

  String _friendly(Object e) {
    final msg = e.toString();
    final lower = msg.toLowerCase();
    if (lower.contains('socketexception') ||
        lower.contains('failed host lookup') ||
        lower.contains('network is unreachable') ||
        lower.contains('connection')) {
      return 'Sin conexión a internet.';
    }
    if (lower.contains('row-level security') ||
        lower.contains('permission') ||
        lower.contains('403') ||
        lower.contains('42501')) {
      return 'No tienes permiso de compras en este negocio.';
    }
    if (msg.isNotEmpty && msg.length < 160 && !lower.contains('exception:')) {
      return msg.replaceFirst('PurchasingException: ', '');
    }
    return 'No se pudo completar la operación. Intenta de nuevo.';
  }
}

final purchaseOrdersViewModelProvider =
    StateNotifierProvider<PurchaseOrdersViewModel, PurchaseOrdersState>(
  (ref) => PurchaseOrdersViewModel(ref),
);
