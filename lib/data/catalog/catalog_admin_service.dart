import 'package:flutter/material.dart' show TimeOfDay;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/ids/uuid_v4.dart';
import '../../domain/catalog/admin_product.dart';
import '../../domain/catalog/catalog_options.dart';
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
    // Mismo shape que consulta el POS (products_queries.dart), con los embeds
    // de las tablas satélite para hidratar el formulario de edición.
    const fullSelect =
        'id, name, price, is_active, category_id, description, tax_mode, sku, '
        'barcode, cost, presentation, item_type, print_area_code, has_variants, '
        'categories(name), menu_item_links(menu_id), menu_item_taxes(tax_id), '
        'menu_item_print_areas(print_area_id)';
    List<dynamic> rows;
    try {
      rows = await _client
          .from('menu_items')
          .select(fullSelect)
          .eq('business_id', businessId)
          .order('name');
    } on PostgrestException {
      // Backend sin alguna migración reciente (p.ej. menu_item_print_areas):
      // degradar al select básico para no tumbar la pantalla.
      rows = await _client
          .from('menu_items')
          .select('id, name, price, is_active, category_id, description, tax_mode, categories(name)')
          .eq('business_id', businessId)
          .order('name');
    }
    return List<Map<String, dynamic>>.from(rows)
        .map(AdminProduct.fromJson)
        .toList(growable: false);
  }

  Future<List<MenuOption>> loadMenus(String businessId) async {
    final rows = await _client
        .from('menus')
        .select('id, name')
        .eq('business_id', businessId)
        .eq('is_active', true)
        .order('name');
    return List<Map<String, dynamic>>.from(rows)
        .map(MenuOption.fromJson)
        .toList(growable: false);
  }

  Future<List<TaxOption>> loadTaxes(String businessId) async {
    final rows = await _client
        .from('taxes')
        .select('id, name, rate')
        .eq('business_id', businessId)
        .eq('is_active', true)
        .order('name');
    return List<Map<String, dynamic>>.from(rows)
        .map(TaxOption.fromJson)
        .toList(growable: false);
  }

  Future<List<PrintAreaOption>> loadPrintAreas(String businessId) async {
    List<dynamic> rows;
    try {
      rows = await _client
          .from('print_areas')
          .select('id, name, code, color, display_order')
          .eq('business_id', businessId)
          .eq('is_active', true)
          .order('display_order')
          .order('name');
    } on PostgrestException {
      // Sin la migración de metadata visual (color/display_order).
      rows = await _client
          .from('print_areas')
          .select('id, name, code')
          .eq('business_id', businessId)
          .eq('is_active', true)
          .order('name');
    }
    return List<Map<String, dynamic>>.from(rows)
        .map(PrintAreaOption.fromJson)
        .toList(growable: false);
  }

  Future<List<ProductCategory>> loadCategories(String businessId) async =>
      (await loadCategoriesForAdmin(businessId)).categories;

  /// Categorías en el orden del POS (`position`, luego nombre), activas e
  /// inactivas. `categories.color` lo usa el POS pero no está en las
  /// migraciones: si la columna no existe se lee sin ella y
  /// [supportsColor] queda en false (la pantalla oculta el selector).
  Future<({List<ProductCategory> categories, bool supportsColor})>
      loadCategoriesForAdmin(String businessId) async {
    List<dynamic> rows;
    var supportsColor = true;
    try {
      rows = await _client
          .from('categories')
          .select('id, name, position, is_active, color')
          .eq('business_id', businessId)
          .order('position')
          .order('name');
    } on PostgrestException {
      supportsColor = false;
      rows = await _client
          .from('categories')
          .select('id, name, position, is_active')
          .eq('business_id', businessId)
          .order('position')
          .order('name');
    }
    return (
      categories: List<Map<String, dynamic>>.from(rows)
          .map(ProductCategory.fromJson)
          .toList(growable: false),
      supportsColor: supportsColor,
    );
  }

  /// Cuántos productos tiene cada categoría (`category_id → n`).
  Future<Map<String, int>> loadCategoryProductCounts(String businessId) async {
    final rows = await _client
        .from('menu_items')
        .select('category_id')
        .eq('business_id', businessId);
    final counts = <String, int>{};
    for (final row in List<Map<String, dynamic>>.from(rows)) {
      final id = row['category_id']?.toString();
      if (id != null && id.isNotEmpty) counts[id] = (counts[id] ?? 0) + 1;
    }
    return counts;
  }

  /// Crea una categoría. Espejo de `CategoryRepository.create` del POS:
  /// `categories.id` no tiene default en la base, el cliente genera el uuid.
  Future<void> createCategory({
    required String businessId,
    required String name,
    required int position,
    String? color,
  }) async {
    await _client.from('categories').insert({
      'id': uuidV4(),
      'business_id': businessId,
      'name': name,
      'position': position,
      'is_active': true,
      'color': ?color,
    });
  }

  /// Edita una categoría. [color] solo se envía si [writeColor] (la columna
  /// puede no existir); null limpia el color.
  Future<void> updateCategory({
    required String id,
    required String name,
    required bool isActive,
    String? color,
    bool writeColor = false,
  }) async {
    await _client.from('categories').update({
      'name': name,
      'is_active': isActive,
      if (writeColor) 'color': color,
    }).eq('id', id);
  }

  Future<void> setCategoryActive(String id, bool isActive) async {
    await _client.from('categories').update({'is_active': isActive}).eq('id', id);
  }

  /// Elimina una categoría vacía. Con productos no se borra (la FK de
  /// `menu_items.category_id` lo impediría y el POS los dejaría sin grupo):
  /// hay que moverlos a otra categoría o desactivarla.
  Future<void> deleteCategory(String id) async {
    final used = await _client
        .from('menu_items')
        .select('id')
        .eq('category_id', id)
        .limit(1);
    if ((used as List).isNotEmpty) {
      throw const CatalogException(
        'La categoría tiene productos. Muévelos a otra categoría o desactívala en su lugar.',
      );
    }
    try {
      await _client.from('categories').delete().eq('id', id);
    } on PostgrestException catch (e) {
      if (e.code == '23503') {
        throw const CatalogException(
          'No se puede eliminar: la categoría está en uso. Desactívala en su lugar.',
        );
      }
      rethrow;
    }
  }

  /// Guarda el orden nuevo en `position` (pasos de 10, como el POS). Solo
  /// escribe las que cambiaron.
  Future<void> reorderCategories(List<ProductCategory> ordered) async {
    for (var i = 0; i < ordered.length; i++) {
      final newPos = (i + 1) * 10;
      if (ordered[i].position == newPos) continue;
      await _client
          .from('categories')
          .update({'position': newPos})
          .eq('id', ordered[i].id);
    }
  }

  /// Activa/desactiva un producto (igual que el POS: `is_active`).
  Future<void> setProductActive(String id, bool isActive) async {
    await _client.from('menu_items').update({'is_active': isActive}).eq('id', id);
  }

  /// Crea un producto. Espejo de `products_repository.createProduct` del POS:
  /// mismas columnas en `menu_items` y mismas tablas satélite
  /// (`menu_item_links`, `menu_item_taxes`, `menu_item_print_areas`).
  /// Imagen, variaciones e inventario no se gestionan desde el dashboard.
  Future<void> createProduct({
    required String businessId,
    required String name,
    required double price,
    String? categoryId,
    String? description,
    String taxMode = 'exclusive',
    String? sku,
    String? barcode,
    double? cost,
    String? presentation,
    String itemType = 'standard',
    String? printAreaCode,
    String? menuId,
    List<String> taxIds = const [],
    List<String> printAreaIds = const [],
  }) async {
    final inserted = await _client
        .from('menu_items')
        .insert(
          {
            'business_id': businessId,
            'name': name,
            'price': price,
            'tax_mode': taxMode,
            'category_id': categoryId,
            'sku': sku,
            'is_active': true,
            'description': description,
            'cost': cost,
            'barcode': barcode,
            'item_type': itemType,
            'print_area_code': printAreaCode,
            'presentation': presentation,
          }..removeWhere((key, value) =>
              value == null || (value is String && value.isEmpty)),
        )
        .select('id')
        .single();

    final itemId = inserted['id']?.toString();
    if (itemId == null || itemId.isEmpty) return;
    await _writeProductSatellites(
      itemId: itemId,
      menuId: menuId,
      taxIds: taxIds,
      printAreaIds: printAreaIds,
      isNew: true,
    );
  }

  /// Edita un producto. Espejo de `products_repository.updateProduct` del POS
  /// (los null se descartan, igual que allá) + delete-all/re-insert de las
  /// tablas satélite, como hace el POS.
  Future<void> updateProduct({
    required String id,
    required String name,
    required double price,
    String? categoryId,
    String? description,
    required String taxMode,
    required bool isActive,
    String? sku,
    String? barcode,
    double? cost,
    String? presentation,
    String itemType = 'standard',
    String? printAreaCode,
    String? menuId,
    List<String> taxIds = const [],
    List<String> printAreaIds = const [],
  }) async {
    await _client.from('menu_items').update({
      'name': name,
      'price': price,
      'tax_mode': taxMode,
      'category_id': categoryId,
      'sku': sku,
      'is_active': isActive,
      'description': description,
      'cost': cost,
      'barcode': barcode,
      'item_type': itemType,
      // Igual que el POS: sin área queda null (el envío a cocina lo avisa).
      'print_area_code':
          (printAreaCode == null || printAreaCode.isEmpty) ? null : printAreaCode,
      if (presentation != null && presentation.isNotEmpty)
        'presentation': presentation,
    }..removeWhere((key, value) =>
        value == null &&
        key != 'print_area_code' &&
        key != 'category_id' &&
        key != 'description')).eq('id', id);

    await _writeProductSatellites(
      itemId: id,
      menuId: menuId,
      taxIds: taxIds,
      printAreaIds: printAreaIds,
      isNew: false,
    );
  }

  /// Publicación en menú, impuestos y áreas de impresión — como el POS:
  /// al editar, delete-all + re-insert.
  Future<void> _writeProductSatellites({
    required String itemId,
    required String? menuId,
    required List<String> taxIds,
    required List<String> printAreaIds,
    required bool isNew,
  }) async {
    if (!isNew) {
      await _client.from('menu_item_links').delete().eq('item_id', itemId);
      await _client.from('menu_item_taxes').delete().eq('item_id', itemId);
    }
    if (menuId != null && menuId.isNotEmpty) {
      await _client.from('menu_item_links').insert({
        'item_id': itemId,
        'menu_id': menuId,
        'position': 0,
      });
    }
    if (taxIds.isNotEmpty) {
      await _client.from('menu_item_taxes').insert([
        for (final taxId in taxIds) {'item_id': itemId, 'tax_id': taxId},
      ]);
    }
    // N:M de áreas (tabla de la migración printing v2); si el backend no la
    // tiene, el code legacy en menu_items.print_area_code ya quedó escrito.
    try {
      if (!isNew) {
        await _client
            .from('menu_item_print_areas')
            .delete()
            .eq('menu_item_id', itemId);
      }
      if (printAreaIds.isNotEmpty) {
        await _client.from('menu_item_print_areas').insert([
          for (final areaId in printAreaIds)
            {'menu_item_id': itemId, 'print_area_id': areaId},
        ]);
      }
    } on PostgrestException {
      // Tabla ausente en backends viejos — ignorar.
    }
  }

  /// Elimina un producto. Si una FK lo impide (ya se vendió: `order_items`,
  /// ofertas, grupos de modificadores…), lanza un error amable; el llamador
  /// puede ofrecer desactivarlo en su lugar.
  Future<void> deleteProduct(String id) async {
    try {
      await _client.from('menu_items').delete().eq('id', id);
    } on PostgrestException catch (e) {
      if (e.code == '23503') {
        throw const CatalogException(
          'No se puede eliminar: el producto tiene ventas u ofertas asociadas. Desactívalo en su lugar.',
        );
      }
      rethrow;
    }
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
