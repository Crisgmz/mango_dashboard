import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/di/providers.dart';
import '../../../domain/catalog/admin_product.dart';
import '../../../domain/catalog/catalog_options.dart';
import '../../../domain/catalog/product_category.dart';

/// Datos del formulario de producto (crear/editar) — mismos campos que edita
/// el POS (menos imagen/variaciones/inventario).
class ProductDraft {
  const ProductDraft({
    required this.name,
    required this.price,
    this.categoryId,
    this.description,
    this.taxMode = 'exclusive',
    this.isActive = true,
    this.sku,
    this.barcode,
    this.cost,
    this.presentation,
    this.itemType = 'standard',
    this.printAreaCode,
    this.menuId,
    this.taxIds = const [],
    this.printAreaIds = const [],
  });

  final String name;
  final double price;
  final String? categoryId;
  final String? description;
  final String taxMode;
  final bool isActive;
  final String? sku;
  final String? barcode;
  final double? cost;
  final String? presentation;
  final String itemType;
  final String? printAreaCode;
  final String? menuId;
  final List<String> taxIds;
  final List<String> printAreaIds;
}

class ProductsAdminState {
  const ProductsAdminState({
    this.isLoading = false,
    this.products = const [],
    this.categories = const [],
    this.menus = const [],
    this.taxes = const [],
    this.printAreas = const [],
    this.error,
    this.savingIds = const {},
    this.saving = false,
  });

  final bool isLoading;
  final List<AdminProduct> products;
  final List<ProductCategory> categories;
  final List<MenuOption> menus;
  final List<TaxOption> taxes;
  final List<PrintAreaOption> printAreas;
  final String? error;

  /// Ids de productos cuyo toggle está en curso (para deshabilitar el switch).
  final Set<String> savingIds;

  /// True mientras un create/update/delete está en curso.
  final bool saving;

  bool get isEmpty => products.isEmpty;

  ProductsAdminState copyWith({
    bool? isLoading,
    List<AdminProduct>? products,
    List<ProductCategory>? categories,
    List<MenuOption>? menus,
    List<TaxOption>? taxes,
    List<PrintAreaOption>? printAreas,
    String? error,
    Set<String>? savingIds,
    bool? saving,
    bool clearError = false,
  }) {
    return ProductsAdminState(
      isLoading: isLoading ?? this.isLoading,
      products: products ?? this.products,
      categories: categories ?? this.categories,
      menus: menus ?? this.menus,
      taxes: taxes ?? this.taxes,
      printAreas: printAreas ?? this.printAreas,
      error: clearError ? null : (error ?? this.error),
      savingIds: savingIds ?? this.savingIds,
      saving: saving ?? this.saving,
    );
  }
}

class ProductsAdminViewModel extends StateNotifier<ProductsAdminState> {
  ProductsAdminViewModel(this._ref) : super(const ProductsAdminState());

  final Ref _ref;

  Future<void> load(String businessId) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final service = _ref.read(catalogAdminServiceProvider);
      final results = await Future.wait([
        service.loadProducts(businessId),
        service.loadCategories(businessId),
        service.loadMenus(businessId),
        service.loadTaxes(businessId),
        service.loadPrintAreas(businessId),
      ]);
      state = state.copyWith(
        isLoading: false,
        products: results[0] as List<AdminProduct>,
        categories: results[1] as List<ProductCategory>,
        menus: results[2] as List<MenuOption>,
        taxes: results[3] as List<TaxOption>,
        printAreas: results[4] as List<PrintAreaOption>,
        clearError: true,
      );
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

  /// Crea un producto. Devuelve true si guardó OK.
  Future<bool> create(String businessId, ProductDraft d) async {
    state = state.copyWith(saving: true, clearError: true);
    try {
      await _ref.read(catalogAdminServiceProvider).createProduct(
            businessId: businessId,
            name: d.name,
            price: d.price,
            categoryId: d.categoryId,
            description: d.description,
            taxMode: d.taxMode,
            sku: d.sku,
            barcode: d.barcode,
            cost: d.cost,
            presentation: d.presentation,
            itemType: d.itemType,
            printAreaCode: d.printAreaCode,
            menuId: d.menuId,
            taxIds: d.taxIds,
            printAreaIds: d.printAreaIds,
          );
      await refresh(businessId);
      state = state.copyWith(saving: false);
      return true;
    } catch (e) {
      state = state.copyWith(saving: false, error: _friendly(e));
      return false;
    }
  }

  /// Edita un producto existente. Devuelve true si guardó OK.
  Future<bool> update(String businessId, String id, ProductDraft d) async {
    state = state.copyWith(saving: true, clearError: true);
    try {
      await _ref.read(catalogAdminServiceProvider).updateProduct(
            id: id,
            name: d.name,
            price: d.price,
            categoryId: d.categoryId,
            description: d.description,
            taxMode: d.taxMode,
            isActive: d.isActive,
            sku: d.sku,
            barcode: d.barcode,
            cost: d.cost,
            presentation: d.presentation,
            itemType: d.itemType,
            printAreaCode: d.printAreaCode,
            menuId: d.menuId,
            taxIds: d.taxIds,
            printAreaIds: d.printAreaIds,
          );
      await refresh(businessId);
      state = state.copyWith(saving: false);
      return true;
    } catch (e) {
      state = state.copyWith(saving: false, error: _friendly(e));
      return false;
    }
  }

  /// Elimina un producto. Devuelve mensaje de error si falla (null si OK).
  Future<String?> delete(String businessId, String id) async {
    state = state.copyWith(saving: true, clearError: true);
    try {
      await _ref.read(catalogAdminServiceProvider).deleteProduct(id);
      await refresh(businessId);
      state = state.copyWith(saving: false);
      return null;
    } catch (e) {
      final msg = _friendly(e);
      state = state.copyWith(saving: false, error: msg);
      return msg;
    }
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
    final msg = e.toString();
    final lower = msg.toLowerCase();
    if (lower.contains('socketexception') ||
        lower.contains('failed host lookup') ||
        lower.contains('network is unreachable') ||
        lower.contains('connection')) {
      return 'Sin conexión a internet.';
    }
    if (lower.contains('row-level security') || lower.contains('permission') || lower.contains('403')) {
      return 'No tienes permiso para modificar este negocio.';
    }
    // CatalogException u otros mensajes ya legibles.
    if (msg.isNotEmpty && msg.length < 160 && !lower.contains('exception:')) {
      return msg.replaceFirst('CatalogException: ', '');
    }
    return 'No se pudo completar la operación. Intenta de nuevo.';
  }
}

final productsAdminViewModelProvider =
    StateNotifierProvider<ProductsAdminViewModel, ProductsAdminState>(
  (ref) => ProductsAdminViewModel(ref),
);
