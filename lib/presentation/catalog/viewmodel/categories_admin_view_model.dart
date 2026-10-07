import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../app/di/providers.dart';
import '../../../data/catalog/catalog_admin_service.dart';
import '../../../domain/catalog/product_category.dart';

class CategoriesAdminState {
  const CategoriesAdminState({
    this.isLoading = false,
    this.categories = const [],
    this.productCounts = const {},
    this.supportsColor = false,
    this.saving = false,
    this.savingIds = const {},
    this.error,
  });

  final bool isLoading;

  /// En el orden del POS (`position`).
  final List<ProductCategory> categories;

  /// `category_id → cantidad de productos`.
  final Map<String, int> productCounts;

  /// El backend tiene `categories.color` (si no, se oculta el selector).
  final bool supportsColor;

  /// True mientras un create/update/delete/reorder está en curso.
  final bool saving;

  /// Ids cuyo switch de visibilidad está guardando.
  final Set<String> savingIds;
  final String? error;

  CategoriesAdminState copyWith({
    bool? isLoading,
    List<ProductCategory>? categories,
    Map<String, int>? productCounts,
    bool? supportsColor,
    bool? saving,
    Set<String>? savingIds,
    String? error,
    bool clearError = false,
  }) {
    return CategoriesAdminState(
      isLoading: isLoading ?? this.isLoading,
      categories: categories ?? this.categories,
      productCounts: productCounts ?? this.productCounts,
      supportsColor: supportsColor ?? this.supportsColor,
      saving: saving ?? this.saving,
      savingIds: savingIds ?? this.savingIds,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

class CategoriesAdminViewModel extends StateNotifier<CategoriesAdminState> {
  CategoriesAdminViewModel(this._ref) : super(const CategoriesAdminState());

  final Ref _ref;

  CatalogAdminService get _service => _ref.read(catalogAdminServiceProvider);

  Future<void> load(String businessId) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final results = await Future.wait([
        _service.loadCategoriesForAdmin(businessId),
        _service.loadCategoryProductCounts(businessId),
      ]);
      final loaded =
          results[0]
              as ({List<ProductCategory> categories, bool supportsColor});
      state = state.copyWith(
        isLoading: false,
        categories: loaded.categories,
        supportsColor: loaded.supportsColor,
        productCounts: results[1] as Map<String, int>,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: 'No se pudieron cargar las categorías: ${_message(e)}',
      );
    }
  }

  Future<void> refresh(String businessId) => load(businessId);

  /// Crea una categoría al final del orden. Devuelve un error o null.
  Future<String?> create(
    String businessId, {
    required String name,
    String? color,
  }) {
    final last = state.categories.fold<int>(
      0,
      (max, c) => c.position > max ? c.position : max,
    );
    return _mutate(businessId, () {
      return _service.createCategory(
        businessId: businessId,
        name: name,
        position: last + 10,
        color: state.supportsColor ? color : null,
      );
    });
  }

  Future<String?> update(
    String businessId,
    ProductCategory category, {
    required String name,
    String? color,
  }) {
    return _mutate(businessId, () {
      return _service.updateCategory(
        id: category.id,
        name: name,
        isActive: category.isActive,
        color: color,
        writeColor: state.supportsColor,
      );
    });
  }

  Future<String?> delete(String businessId, ProductCategory category) {
    return _mutate(businessId, () => _service.deleteCategory(category.id));
  }

  /// Mostrar/ocultar en el POS, optimista.
  Future<void> toggleActive(ProductCategory category, bool isActive) async {
    final previous = state.categories;
    state = state.copyWith(
      categories: [
        for (final c in previous)
          c.id == category.id ? c.copyWith(isActive: isActive) : c,
      ],
      savingIds: {...state.savingIds, category.id},
      clearError: true,
    );
    try {
      await _service.setCategoryActive(category.id, isActive);
    } catch (e) {
      state = state.copyWith(
        categories: previous,
        error: 'No se pudo actualizar la categoría: ${_message(e)}',
      );
    } finally {
      state = state.copyWith(
        savingIds: {...state.savingIds}..remove(category.id),
      );
    }
  }

  /// Reordena (índices ya ajustados por `onReorderItem`), optimista.
  Future<void> reorder(String businessId, int oldIndex, int newIndex) async {
    final list = [...state.categories];
    final moved = list.removeAt(oldIndex);
    list.insert(newIndex, moved);
    state = state.copyWith(categories: list, saving: true, clearError: true);
    try {
      await _service.reorderCategories(list);
      state = state.copyWith(
        saving: false,
        categories: [
          for (var i = 0; i < list.length; i++)
            list[i].copyWith(position: (i + 1) * 10),
        ],
      );
    } catch (e) {
      state = state.copyWith(
        saving: false,
        error: 'No se pudo guardar el orden: ${_message(e)}',
      );
      await load(businessId);
    }
  }

  Future<String?> _mutate(String businessId, Future<void> Function() op) async {
    state = state.copyWith(saving: true, clearError: true);
    try {
      await op();
      state = state.copyWith(saving: false);
      await load(businessId);
      return null;
    } catch (e) {
      state = state.copyWith(saving: false);
      return _message(e);
    }
  }

  String _message(Object e) {
    if (e is CatalogException) return e.message;
    if (e is PostgrestException) {
      if (e.code == '42501') return 'No tienes permiso para esta operación.';
      if (e.code == '23505') return 'Ya existe una categoría con ese nombre.';
      return e.message;
    }
    return e.toString();
  }
}

final categoriesAdminViewModelProvider =
    StateNotifierProvider<CategoriesAdminViewModel, CategoriesAdminState>(
      (ref) => CategoriesAdminViewModel(ref),
    );
