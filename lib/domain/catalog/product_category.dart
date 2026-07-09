import 'package:flutter/foundation.dart';

/// Categoría de productos (tabla `categories`). Para agrupar y para el selector
/// de "aplica a" en las ofertas.
@immutable
class ProductCategory {
  const ProductCategory({required this.id, required this.name});

  final String id;
  final String name;

  factory ProductCategory.fromJson(Map<String, dynamic> json) {
    return ProductCategory(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? 'Categoría',
    );
  }
}
