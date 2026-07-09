import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/di/providers.dart';
import '../../../domain/catalog/admin_product.dart';

class ProductsAdminState {
  const ProductsAdminState({
    this.isLoading = false,
    this.products = const [],
    this.error,
    this.savingIds = const {},
  });

  final bool isLoading;
  final List<AdminProduct> products;
  final String? error;

  /// Ids de productos cuyo toggle está en curso (para deshabilitar el switch).
  final Set<String> savingIds;

  bool get isEmpty => products.isEmpty;

  ProductsAdminState copyWith({
    bool? isLoading,
    List<AdminProduct>? products,
    String? error,
    Set<String>? savingIds,
    bool clearError = false,
  }) {
    return ProductsAdminState(
      isLoading: isLoading ?? this.isLoading,
      products: products ?? this.products,
      error: clearError ? null : (error ?? this.error),
      savingIds: savingIds ?? this.savingIds,
    );
  }
}

class ProductsAdminViewModel extends StateNotifier<ProductsAdminState> {
  ProductsAdminViewModel(this._ref) : super(const ProductsAdminState());

  final Ref _ref;

  Future<void> load(String businessId) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final products = await _ref.read(catalogAdminServiceProvider).loadProducts(businessId);
      state = state.copyWith(isLoading: false, products: products, clearError: true);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: _friendly(e));
    }
  }

  Future<void> refresh(String businessId) async {
    try {
      final products = await _ref.read(catalogAdminServiceProvider).loadProducts(businessId);
      state = state.copyWith(products: products, clearError: true);
    } catch (_) {/* conserva los datos en pantalla */}
  }

  /// Activa/desactiva un producto de forma optimista; revierte si falla.
  Future<void> toggle(String id, bool value) async {
    final before = state.products;
    state = state.copyWith(
      products: [
        for (final p in before) p.id == id ? p.copyWith(isActive: value) : p,
      ],
      savingIds: {...state.savingIds, id},
      clearError: true,
    );
    try {
      await _ref.read(catalogAdminServiceProvider).setProductActive(id, value);
      state = state.copyWith(savingIds: {...state.savingIds}..remove(id));
    } catch (e) {
      state = state.copyWith(
        products: before, // revertir
        savingIds: {...state.savingIds}..remove(id),
        error: _friendly(e),
      );
    }
  }

  String _friendly(Object e) {
    final msg = e.toString().toLowerCase();
    if (msg.contains('socketexception') ||
        msg.contains('failed host lookup') ||
        msg.contains('network is unreachable') ||
        msg.contains('connection')) {
      return 'Sin conexión a internet.';
    }
    if (msg.contains('row-level security') || msg.contains('permission') || msg.contains('403')) {
      return 'No tienes permiso para modificar este negocio.';
    }
    return 'No se pudo completar la operación. Intenta de nuevo.';
  }
}

final productsAdminViewModelProvider =
    StateNotifierProvider<ProductsAdminViewModel, ProductsAdminState>(
  (ref) => ProductsAdminViewModel(ref),
);
