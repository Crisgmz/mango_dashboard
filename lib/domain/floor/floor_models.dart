import 'package:flutter/foundation.dart';

/// Zona del salón (tabla `zones`): Salón principal, Terraza, Barra…
@immutable
class FloorZone {
  const FloorZone({
    required this.id,
    required this.name,
    this.sortIndex = 0,
    this.isActive = true,
  });

  final String id;
  final String name;

  /// Orden en el POS (`sort_index`, pasos de 10; 900/901 son las zonas
  /// virtuales de venta manual/rápida, que no se administran aquí).
  final int sortIndex;
  final bool isActive;

  factory FloorZone.fromJson(Map<String, dynamic> json) {
    return FloorZone(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? 'Zona',
      sortIndex: (json['sort_index'] as num?)?.toInt() ?? 0,
      isActive: json['is_active'] as bool? ?? true,
    );
  }

  FloorZone copyWith({String? name, int? sortIndex, bool? isActive}) {
    return FloorZone(
      id: id,
      name: name ?? this.name,
      sortIndex: sortIndex ?? this.sortIndex,
      isActive: isActive ?? this.isActive,
    );
  }
}

/// Mesa (tabla `dining_tables`). `code` es único por zona; `label` es el
/// nombre que muestra el POS (si falta, se usa el código).
@immutable
class FloorTable {
  const FloorTable({
    required this.id,
    required this.zoneId,
    required this.code,
    this.label,
    this.capacity = 4,
    this.isActive = true,
    this.state = 'available',
  });

  final String id;
  final String zoneId;
  final String code;
  final String? label;
  final int capacity;
  final bool isActive;

  /// `table_state`: available | occupied | reserved | blocked.
  final String state;

  String get displayName {
    final l = label?.trim();
    return (l == null || l.isEmpty) ? code : l;
  }

  bool get isAvailable => state == 'available';

  /// Etiqueta del estado cuando NO está libre (null si está libre).
  String? get stateLabel {
    switch (state) {
      case 'available':
        return null;
      case 'occupied':
        return 'Ocupada';
      case 'reserved':
        return 'Reservada';
      case 'blocked':
        return 'Bloqueada';
      default:
        return state;
    }
  }

  factory FloorTable.fromJson(Map<String, dynamic> json) {
    final label = json['label']?.toString().trim();
    return FloorTable(
      id: json['id']?.toString() ?? '',
      zoneId: json['zone_id']?.toString() ?? '',
      code: json['code']?.toString() ?? '',
      label: (label == null || label.isEmpty) ? null : label,
      capacity: (json['capacity'] as num?)?.toInt() ?? 4,
      isActive: json['is_active'] as bool? ?? true,
      state: json['state']?.toString() ?? 'available',
    );
  }
}

/// Cómo terminó una eliminación: borrado de verdad, o desactivado porque
/// tenía historial de ventas (borrarlo arrastraría ese historial).
enum FloorDeleteOutcome { deleted, deactivated }
