import 'package:flutter/foundation.dart';

/// Producto del menú para gestión administrativa (tabla `menu_items`).
/// Espejo de lo que edita el POS (`add_edit_product_dialog`): mismos campos y
/// mismas tablas satélite (`menu_item_links`, `menu_item_taxes`,
/// `menu_item_print_areas`). El dashboard no gestiona imagen, variaciones ni
/// inventario (eso queda en el POS).
@immutable
class AdminProduct {
  const AdminProduct({
    required this.id,
    required this.name,
    required this.isActive,
    required this.price,
    required this.categoryId,
    required this.categoryName,
    this.description,
    this.taxMode = 'exclusive',
    this.sku,
    this.barcode,
    this.cost,
    this.presentation,
    this.itemType = 'standard',
    this.printAreaCode,
    this.hasVariants = false,
    this.menuId,
    this.taxIds = const [],
    this.printAreaIds = const [],
  });

  final String id;
  final String name;
  final bool isActive;
  final double price;
  final String? categoryId;
  final String? categoryName;
  final String? description;

  /// `exclusive` (el precio no incluye impuestos) o `inclusive`.
  final String taxMode;

  final String? sku;
  final String? barcode;
  final double? cost;

  /// Texto libre: "Botella", "Trago", "Shot"…
  final String? presentation;

  /// `standard` | `combo` | `extra_only`.
  final String itemType;

  /// Code del área de producción/impresión (columna legacy 1:1).
  final String? printAreaCode;

  /// Si tiene variaciones, el precio vive en las variantes (se edita en el POS).
  final bool hasVariants;

  /// Menú donde está publicado (`menu_item_links`, primer link).
  final String? menuId;

  /// Impuestos asignados (`menu_item_taxes.tax_id`).
  final List<String> taxIds;

  /// Áreas de impresión asignadas (`menu_item_print_areas.print_area_id`).
  final List<String> printAreaIds;

  AdminProduct copyWith({bool? isActive}) {
    return AdminProduct(
      id: id,
      name: name,
      isActive: isActive ?? this.isActive,
      price: price,
      categoryId: categoryId,
      categoryName: categoryName,
      description: description,
      taxMode: taxMode,
      sku: sku,
      barcode: barcode,
      cost: cost,
      presentation: presentation,
      itemType: itemType,
      printAreaCode: printAreaCode,
      hasVariants: hasVariants,
      menuId: menuId,
      taxIds: taxIds,
      printAreaIds: printAreaIds,
    );
  }

  factory AdminProduct.fromJson(Map<String, dynamic> json) {
    final cat = json['categories'];

    String? firstId(dynamic rows, String key) {
      if (rows is! List) return null;
      for (final r in rows) {
        if (r is Map && r[key] != null) return r[key].toString();
      }
      return null;
    }

    List<String> allIds(dynamic rows, String key) {
      if (rows is! List) return const [];
      return [
        for (final r in rows)
          if (r is Map && r[key] != null) r[key].toString(),
      ];
    }

    return AdminProduct(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? 'Producto',
      isActive: json['is_active'] != false,
      price: _toDouble(json['price']),
      categoryId: json['category_id']?.toString(),
      categoryName: cat is Map<String, dynamic> ? cat['name']?.toString() : null,
      description: json['description']?.toString(),
      taxMode: json['tax_mode']?.toString() ?? 'exclusive',
      sku: json['sku']?.toString(),
      barcode: json['barcode']?.toString(),
      cost: _toDoubleOrNull(json['cost']),
      presentation: json['presentation']?.toString(),
      itemType: json['item_type']?.toString() ?? 'standard',
      printAreaCode: json['print_area_code']?.toString(),
      hasVariants: json['has_variants'] == true,
      menuId: firstId(json['menu_item_links'], 'menu_id'),
      taxIds: allIds(json['menu_item_taxes'], 'tax_id'),
      printAreaIds: allIds(json['menu_item_print_areas'], 'print_area_id'),
    );
  }

  static double _toDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }

  static double? _toDoubleOrNull(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString());
  }
}
