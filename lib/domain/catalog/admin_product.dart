import 'package:flutter/foundation.dart';

/// Producto del menú para gestión administrativa (tabla `menu_items`).
/// El dashboard solo activa/desactiva (`is_active`); no edita el resto.
@immutable
class AdminProduct {
  const AdminProduct({
    required this.id,
    required this.name,
    required this.isActive,
    required this.price,
    required this.categoryId,
    required this.categoryName,
  });

  final String id;
  final String name;
  final bool isActive;
  final double price;
  final String? categoryId;
  final String? categoryName;

  AdminProduct copyWith({bool? isActive}) {
    return AdminProduct(
      id: id,
      name: name,
      isActive: isActive ?? this.isActive,
      price: price,
      categoryId: categoryId,
      categoryName: categoryName,
    );
  }

  factory AdminProduct.fromJson(Map<String, dynamic> json) {
    final cat = json['categories'];
    return AdminProduct(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? 'Producto',
      isActive: json['is_active'] != false,
      price: _toDouble(json['price']),
      categoryId: json['category_id']?.toString(),
      categoryName: cat is Map<String, dynamic> ? cat['name']?.toString() : null,
    );
  }

  static double _toDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }
}
