import 'package:flutter/material.dart' show TimeOfDay;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/catalog/admin_product.dart';
import '../../domain/catalog/product_category.dart';
import '../../domain/catalog/promotion.dart';
import '../../domain/catalog/promotion_enums.dart';

/// Lectura/escritura de productos y ofertas contra el Supabase compartido con el
/// POS. Replica EXACTAMENTE lo que el POS escribe (mismas tablas y columnas) para
/// que ambos sistemas se lean igual. Sin RPC: mutaciones directas gated por RLS
/// (el usuario owner/admin autenticado, igual que el POS).
class CatalogAdminService {
  CatalogAdminService(this._client);

  final SupabaseClient _client;

  // ── Productos (menu_items) ──

  Future<List<AdminProduct>> loadProducts(String businessId) async {
    final rows = await _client
        .from('menu_items')
        .select('id, name, price, is_active, category_id, categories(name)')
        .eq('business_id', businessId)
        .order('name');
    return List<Map<String, dynamic>>.from(rows)
        .map(AdminProduct.fromJson)
        .toList(growable: false);
  }

  Future<List<ProductCategory>> loadCategories(String businessId) async {
    final rows = await _client
        .from('categories')
        .select('id, name')
        .eq('business_id', businessId)
        .order('name');
    return List<Map<String, dynamic>>.from(rows)
        .map(ProductCategory.fromJson)
        .toList(growable: false);
  }

  /// Activa/desactiva un producto (igual que el POS: `is_active`).
  Future<void> setProductActive(String id, bool isActive) async {
    await _client.from('menu_items').update({'is_active': isActive}).eq('id', id);
  }

  // ── Ofertas (promotions) ──

  Future<List<Promotion>> loadPromotions(String businessId) async {
    final rows = await _client
        .from('promotions')
        .select(
          'id, name, description, discount_type, discount_value, min_purchase, '
          'applies_to, promo_type, target_scope, target_ids, days_of_week, '
          'auto_apply, priority, stackable, buy_quantity, pay_quantity, '
          'reward_quantity, start_date, end_date, start_time, end_time, '
          'is_active, created_at',
        )
        .eq('business_id', businessId)
        .order('priority', ascending: false)
        .order('created_at', ascending: false);
    return List<Map<String, dynamic>>.from(rows)
        .map(Promotion.fromJson)
        .toList(growable: false);
  }

  /// Crea una oferta "simple" (% o monto fijo). `promo_type = discount_type` y
  /// las cantidades BOGO van nulas (descartadas). Espejo de
  /// `promos_repository.createPromotion` del POS.
  Future<void> createPromotion({
    required String businessId,
    required String name,
    String? description,
    required DiscountType discountType,
    required double discountValue,
    required double minPurchase,
    required AppliesTo appliesTo,
    required List<String> targetIds,
    required List<int> daysOfWeek,
    required bool autoApply,
    required bool stackable,
    required int priority,
    required DateTime startDate,
    required DateTime endDate,
    TimeOfDay? startTime,
    TimeOfDay? endTime,
  }) async {
    await _client.from('promotions').insert(
      {
        'business_id': businessId,
        'name': name,
        'description': description,
        'discount_type': discountType.raw,
        'promo_type': discountType.raw,
        'discount_value': discountValue,
        'min_purchase': minPurchase,
        'applies_to': appliesTo.raw,
        'target_scope': appliesTo.raw,
        'target_ids': targetIds,
        'days_of_week': daysOfWeek,
        'auto_apply': autoApply,
        'stackable': stackable,
        'priority': priority,
        'start_date': startDate.toUtc().toIso8601String(),
        'end_date': endDate.toUtc().toIso8601String(),
        'start_time': _fmtTime(startTime),
        'end_time': _fmtTime(endTime),
        'is_active': true,
      }..removeWhere((key, value) {
        if (value == null) return true;
        if (value is String) return value.isEmpty;
        if (value is List) return value.isEmpty && key == 'target_ids';
        return false;
      }),
    );
  }

  /// Edita una oferta simple. Envía todos los campos explícitos (permite limpiar
  /// descripción/horario y cambiar el estado activo). Espejo de
  /// `promos_repository.updatePromotion` del POS.
  /// [promoType] y las cantidades se pasan explícitas para preservar las ofertas
  /// especiales (2x1/combo): al editarles solo el horario no se degradan a %/fijo.
  /// Para ofertas simples, `promoType == discountType.raw` y cantidades null.
  Future<void> updatePromotion({
    required String id,
    required String name,
    String? description,
    required DiscountType discountType,
    required String promoType,
    required double discountValue,
    required double minPurchase,
    required AppliesTo appliesTo,
    required List<String> targetIds,
    required List<int> daysOfWeek,
    required bool autoApply,
    required bool stackable,
    required int priority,
    int? buyQuantity,
    int? payQuantity,
    int? rewardQuantity,
    required DateTime startDate,
    required DateTime endDate,
    TimeOfDay? startTime,
    TimeOfDay? endTime,
    required bool isActive,
  }) async {
    await _client.from('promotions').update({
      'name': name,
      'description': (description == null || description.isEmpty) ? null : description,
      'discount_type': discountType.raw,
      'promo_type': promoType,
      'discount_value': discountValue,
      'min_purchase': minPurchase,
      'applies_to': appliesTo.raw,
      'target_scope': appliesTo.raw,
      'target_ids': targetIds,
      'days_of_week': daysOfWeek,
      'auto_apply': autoApply,
      'stackable': stackable,
      'priority': priority,
      'buy_quantity': buyQuantity,
      'pay_quantity': payQuantity,
      'reward_quantity': rewardQuantity,
      'start_date': startDate.toUtc().toIso8601String(),
      'end_date': endDate.toUtc().toIso8601String(),
      'start_time': _fmtTime(startTime),
      'end_time': _fmtTime(endTime),
      'is_active': isActive,
    }).eq('id', id);
  }

  Future<void> setPromotionActive(String id, bool isActive) async {
    await _client.from('promotions').update({'is_active': isActive}).eq('id', id);
  }

  /// Elimina una oferta. Si una FK lo impide (ej. cupones que la referencian),
  /// lanza un error amable; el llamador puede ofrecer desactivarla en su lugar.
  Future<void> deletePromotion(String id) async {
    try {
      await _client.from('promotions').delete().eq('id', id);
    } on PostgrestException catch (e) {
      if (e.code == '23503') {
        throw const CatalogException(
          'No se puede eliminar: la oferta tiene cupones asociados. Desactívala en su lugar.',
        );
      }
      rethrow;
    }
  }

  /// Serializa una hora de pared a "HH:mm:00" para la columna `time` (sin tz).
  String? _fmtTime(TimeOfDay? value) {
    if (value == null) return null;
    final hh = value.hour.toString().padLeft(2, '0');
    final mm = value.minute.toString().padLeft(2, '0');
    return '$hh:$mm:00';
  }
}

/// Error de dominio del módulo de catálogo, con mensaje apto para mostrar.
class CatalogException implements Exception {
  const CatalogException(this.message);
  final String message;

  @override
  String toString() => message;
}
