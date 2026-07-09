import 'package:flutter/material.dart' show TimeOfDay;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/di/providers.dart';
import '../../../domain/catalog/admin_product.dart';
import '../../../domain/catalog/product_category.dart';
import '../../../domain/catalog/promotion.dart';
import '../../../domain/catalog/promotion_enums.dart';

/// Datos del formulario de oferta (crear/editar). Solo ofertas "simples".
class PromotionDraft {
  const PromotionDraft({
    required this.name,
    required this.description,
    required this.discountType,
    required this.discountValue,
    required this.minPurchase,
    required this.appliesTo,
    required this.targetIds,
    required this.daysOfWeek,
    required this.autoApply,
    required this.stackable,
    required this.priority,
    required this.startDate,
    required this.endDate,
    required this.startTime,
    required this.endTime,
    this.promoType,
    this.buyQuantity,
    this.payQuantity,
    this.rewardQuantity,
  });

  final String name;
  final String? description;
  final DiscountType discountType;
  final double discountValue;
  final double minPurchase;
  final AppliesTo appliesTo;
  final List<String> targetIds;
  final List<int> daysOfWeek;
  final bool autoApply;
  final bool stackable;
  final int priority;
  final DateTime startDate;
  final DateTime endDate;
  final TimeOfDay? startTime;
  final TimeOfDay? endTime;

  /// Solo al editar: tipo crudo a preservar (especiales). Si es null, se usa
  /// `discountType.raw` (oferta simple).
  final String? promoType;
  final int? buyQuantity;
  final int? payQuantity;
  final int? rewardQuantity;
}

class OffersAdminState {
  const OffersAdminState({
    this.isLoading = false,
    this.saving = false,
    this.promotions = const [],
    this.products = const [],
    this.categories = const [],
    this.error,
    this.savingIds = const {},
  });

  final bool isLoading;
  final bool saving;
  final List<Promotion> promotions;
  final List<AdminProduct> products;
  final List<ProductCategory> categories;
  final String? error;
  final Set<String> savingIds;

  OffersAdminState copyWith({
    bool? isLoading,
    bool? saving,
    List<Promotion>? promotions,
    List<AdminProduct>? products,
    List<ProductCategory>? categories,
    String? error,
    Set<String>? savingIds,
    bool clearError = false,
  }) {
    return OffersAdminState(
      isLoading: isLoading ?? this.isLoading,
      saving: saving ?? this.saving,
      promotions: promotions ?? this.promotions,
      products: products ?? this.products,
      categories: categories ?? this.categories,
      error: clearError ? null : (error ?? this.error),
      savingIds: savingIds ?? this.savingIds,
    );
  }
}

class OffersAdminViewModel extends StateNotifier<OffersAdminState> {
  OffersAdminViewModel(this._ref) : super(const OffersAdminState());

  final Ref _ref;

  Future<void> load(String businessId) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final service = _ref.read(catalogAdminServiceProvider);
      final results = await Future.wait([
        service.loadPromotions(businessId),
        service.loadProducts(businessId),
        service.loadCategories(businessId),
      ]);
      state = state.copyWith(
        isLoading: false,
        promotions: results[0] as List<Promotion>,
        products: results[1] as List<AdminProduct>,
        categories: results[2] as List<ProductCategory>,
        clearError: true,
      );
    } catch (e) {
      state = state.copyWith(isLoading: false, error: _friendly(e));
    }
  }

  Future<void> _reloadPromotions(String businessId) async {
    final promos = await _ref.read(catalogAdminServiceProvider).loadPromotions(businessId);
    state = state.copyWith(promotions: promos);
  }

  /// Crea una oferta. Devuelve true si guardó OK.
  Future<bool> create(String businessId, PromotionDraft d) async {
    state = state.copyWith(saving: true, clearError: true);
    try {
      await _ref.read(catalogAdminServiceProvider).createPromotion(
            businessId: businessId,
            name: d.name,
            description: d.description,
            discountType: d.discountType,
            discountValue: d.discountValue,
            minPurchase: d.minPurchase,
            appliesTo: d.appliesTo,
            targetIds: d.targetIds,
            daysOfWeek: d.daysOfWeek,
            autoApply: d.autoApply,
            stackable: d.stackable,
            priority: d.priority,
            startDate: d.startDate,
            endDate: d.endDate,
            startTime: d.startTime,
            endTime: d.endTime,
          );
      await _reloadPromotions(businessId);
      state = state.copyWith(saving: false);
      return true;
    } catch (e) {
      state = state.copyWith(saving: false, error: _friendly(e));
      return false;
    }
  }

  /// Edita una oferta existente. Devuelve true si guardó OK.
  Future<bool> update(String businessId, String id, PromotionDraft d, bool isActive) async {
    state = state.copyWith(saving: true, clearError: true);
    try {
      await _ref.read(catalogAdminServiceProvider).updatePromotion(
            id: id,
            name: d.name,
            description: d.description,
            discountType: d.discountType,
            promoType: d.promoType ?? d.discountType.raw,
            discountValue: d.discountValue,
            minPurchase: d.minPurchase,
            appliesTo: d.appliesTo,
            targetIds: d.targetIds,
            daysOfWeek: d.daysOfWeek,
            autoApply: d.autoApply,
            stackable: d.stackable,
            priority: d.priority,
            buyQuantity: d.buyQuantity,
            payQuantity: d.payQuantity,
            rewardQuantity: d.rewardQuantity,
            startDate: d.startDate,
            endDate: d.endDate,
            startTime: d.startTime,
            endTime: d.endTime,
            isActive: isActive,
          );
      await _reloadPromotions(businessId);
      state = state.copyWith(saving: false);
      return true;
    } catch (e) {
      state = state.copyWith(saving: false, error: _friendly(e));
      return false;
    }
  }

  /// Activa/desactiva una oferta de forma optimista; revierte si falla.
  Future<void> toggleActive(String id, bool value) async {
    final before = state.promotions;
    state = state.copyWith(
      promotions: [
        for (final p in before) p.id == id ? _withActive(p, value) : p,
      ],
      savingIds: {...state.savingIds, id},
      clearError: true,
    );
    try {
      await _ref.read(catalogAdminServiceProvider).setPromotionActive(id, value);
      state = state.copyWith(savingIds: {...state.savingIds}..remove(id));
    } catch (e) {
      state = state.copyWith(
        promotions: before,
        savingIds: {...state.savingIds}..remove(id),
        error: _friendly(e),
      );
    }
  }

  /// Elimina una oferta. Devuelve mensaje de error si falla (null si OK).
  Future<String?> delete(String businessId, String id) async {
    try {
      await _ref.read(catalogAdminServiceProvider).deletePromotion(id);
      await _reloadPromotions(businessId);
      return null;
    } catch (e) {
      final msg = _friendly(e);
      state = state.copyWith(error: msg);
      return msg;
    }
  }

  Promotion _withActive(Promotion p, bool value) => Promotion(
        id: p.id,
        name: p.name,
        description: p.description,
        discountType: p.discountType,
        promoType: p.promoType,
        discountValue: p.discountValue,
        minPurchase: p.minPurchase,
        appliesTo: p.appliesTo,
        targetScope: p.targetScope,
        targetIds: p.targetIds,
        daysOfWeek: p.daysOfWeek,
        autoApply: p.autoApply,
        stackable: p.stackable,
        priority: p.priority,
        buyQuantity: p.buyQuantity,
        payQuantity: p.payQuantity,
        rewardQuantity: p.rewardQuantity,
        startDate: p.startDate,
        endDate: p.endDate,
        startTime: p.startTime,
        endTime: p.endTime,
        isActive: value,
        createdAt: p.createdAt,
      );

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

final offersAdminViewModelProvider =
    StateNotifierProvider<OffersAdminViewModel, OffersAdminState>(
  (ref) => OffersAdminViewModel(ref),
);
