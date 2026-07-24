import 'package:flutter/foundation.dart';

/// Menú del negocio (tabla `menus`). Un producto se publica en un menú vía
/// `menu_item_links` — igual que el POS.
@immutable
class MenuOption {
  const MenuOption({required this.id, required this.name});

  final String id;
  final String name;

  factory MenuOption.fromJson(Map<String, dynamic> json) {
    return MenuOption(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? 'Menú',
    );
  }
}

/// Impuesto del negocio (tabla `taxes`). Se asigna a productos vía la N:M
/// `menu_item_taxes` — la tasa efectiva es la suma de los impuestos activos.
@immutable
class TaxOption {
  const TaxOption({required this.id, required this.name, required this.rate});

  final String id;
  final String name;

  /// Porcentaje 0-100.
  final double rate;

  String get label => '$name (${rate.truncateToDouble() == rate ? rate.toInt() : rate}%)';

  factory TaxOption.fromJson(Map<String, dynamic> json) {
    final raw = json['rate'];
    return TaxOption(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? 'Impuesto',
      rate: raw is num ? raw.toDouble() : double.tryParse(raw?.toString() ?? '') ?? 0,
    );
  }
}

/// Área de impresión / producción (tabla `print_areas`): Cocina caliente, Bar…
/// El producto guarda su `code` en `menu_items.print_area_code` y además la
/// fila N:M en `menu_item_print_areas`, igual que el POS.
@immutable
class PrintAreaOption {
  const PrintAreaOption({
    required this.id,
    required this.name,
    required this.code,
    this.color,
  });

  final String id;
  final String name;
  final String code;

  /// Hex opcional (`#RRGGBB`) para el chip, como en el KDS.
  final String? color;

  factory PrintAreaOption.fromJson(Map<String, dynamic> json) {
    return PrintAreaOption(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? 'Área',
      code: json['code']?.toString() ?? '',
      color: json['color']?.toString(),
    );
  }
}
