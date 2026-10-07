import 'package:flutter/foundation.dart';

/// Categoría de productos (tabla `categories`). Para agrupar, para el selector
/// de "aplica a" en las ofertas y para administrarlas desde el dashboard.
@immutable
class ProductCategory {
  const ProductCategory({
    required this.id,
    required this.name,
    this.position = 0,
    this.isActive = true,
    this.color,
  });

  final String id;
  final String name;

  /// Orden de los botones de categoría en el POS (`position`, pasos de 10).
  final int position;

  /// Visible en la pantalla de ventas del POS.
  final bool isActive;

  /// `#RRGGBB` del botón en el POS, o null.
  final String? color;

  factory ProductCategory.fromJson(Map<String, dynamic> json) {
    final color = json['color']?.toString().trim();
    return ProductCategory(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? 'Categoría',
      position: (json['position'] as num?)?.toInt() ?? 0,
      isActive: json['is_active'] as bool? ?? true,
      color: (color == null || color.isEmpty) ? null : color,
    );
  }

  ProductCategory copyWith({
    String? name,
    int? position,
    bool? isActive,
    Object? color = _unset,
  }) {
    return ProductCategory(
      id: id,
      name: name ?? this.name,
      position: position ?? this.position,
      isActive: isActive ?? this.isActive,
      color: identical(color, _unset) ? this.color : color as String?,
    );
  }
}

const Object _unset = Object();

/// Colores que ofrece el POS para los botones de categoría (mismos valores que
/// `categories_view.dart` del POS, para que ambos lados elijan de la misma
/// paleta). Son datos que se guardan en `categories.color`, no colores de UI.
const kCategoryColorPalette = <String>[
  '#EF4444', // rojo
  '#F97316', // naranja
  '#EAB308', // amarillo
  '#22C55E', // verde
  '#14B8A6', // teal
  '#3B82F6', // azul
  '#6366F1', // índigo
  '#A855F7', // morado
  '#EC4899', // rosa
  '#92400E', // marrón
  '#6B7280', // gris
];
