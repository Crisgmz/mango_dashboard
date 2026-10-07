import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/di/providers.dart';
import '../../../data/floor/floor_admin_service.dart';
import '../../../domain/floor/floor_models.dart';

class FloorAdminState {
  const FloorAdminState({
    this.isLoading = false,
    this.zones = const [],
    this.tables = const [],
    this.saving = false,
    this.error,
  });

  final bool isLoading;

  /// En el orden del POS (`sort_index`).
  final List<FloorZone> zones;
  final List<FloorTable> tables;

  /// True mientras una operación está en curso.
  final bool saving;
  final String? error;

  List<FloorZone> get activeZones =>
      zones.where((z) => z.isActive).toList(growable: false);

  List<FloorZone> get inactiveZones =>
      zones.where((z) => !z.isActive).toList(growable: false);

  FloorZone? zoneById(String id) {
    for (final z in zones) {
      if (z.id == id) return z;
    }
    return null;
  }

  /// Mesas de la zona en orden natural de código (T2 antes que T10).
  List<FloorTable> tablesOf(String zoneId, {required bool active}) {
    return tables
        .where((t) => t.zoneId == zoneId && t.isActive == active)
        .toList()
      ..sort((a, b) => naturalCompare(a.code, b.code));
  }

  FloorAdminState copyWith({
    bool? isLoading,
    List<FloorZone>? zones,
    List<FloorTable>? tables,
    bool? saving,
    String? error,
    bool clearError = false,
  }) {
    return FloorAdminState(
      isLoading: isLoading ?? this.isLoading,
      zones: zones ?? this.zones,
      tables: tables ?? this.tables,
      saving: saving ?? this.saving,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

/// Código de la mesa número [n] al crear varias: el número se rellena con
/// ceros al largo de [to] (mínimo 2, como el POS): T01…T20, T001…T150.
String bulkTableCode(String prefix, int n, int to) {
  final width = to.toString().length < 2 ? 2 : to.toString().length;
  return '${prefix.trim()}${n.toString().padLeft(width, '0')}';
}

/// Compara códigos como los ordena una persona: "T2" < "T10".
int naturalCompare(String a, String b) {
  final re = RegExp(r'(\d+)|(\D+)');
  final pa = re.allMatches(a.toLowerCase()).map((m) => m.group(0)!).toList();
  final pb = re.allMatches(b.toLowerCase()).map((m) => m.group(0)!).toList();
  for (var i = 0; i < pa.length && i < pb.length; i++) {
    final na = int.tryParse(pa[i]);
    final nb = int.tryParse(pb[i]);
    final c = (na != null && nb != null)
        ? na.compareTo(nb)
        : pa[i].compareTo(pb[i]);
    if (c != 0) return c;
  }
  return pa.length.compareTo(pb.length);
}

class FloorAdminViewModel extends StateNotifier<FloorAdminState> {
  FloorAdminViewModel(this._ref) : super(const FloorAdminState());

  final Ref _ref;

  FloorAdminService get _service => _ref.read(floorAdminServiceProvider);

  Future<void> load(String businessId) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final floor = await _service.loadFloor(businessId);
      state = state.copyWith(
        isLoading: false,
        zones: floor.zones,
        tables: floor.tables,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: 'No se pudo cargar el salón: $e',
      );
    }
  }

  Future<void> refresh(String businessId) => load(businessId);

  // ── Zonas ──

  /// Crea una zona al final del orden. Devuelve un error o null.
  Future<String?> createZone(String businessId, String name) {
    final clean = name.trim();
    if (clean.isEmpty) return Future.value('Escribe el nombre de la zona.');
    final last = state.zones
        .where((z) => z.sortIndex < 900)
        .fold<int>(0, (max, z) => z.sortIndex > max ? z.sortIndex : max);
    return _mutate(businessId, () {
      return _service.createZone(
        businessId: businessId,
        name: clean,
        sortIndex: last + 10,
      );
    });
  }

  Future<String?> renameZone(String businessId, FloorZone zone, String name) {
    final clean = name.trim();
    if (clean.isEmpty) return Future.value('Escribe el nombre de la zona.');
    return _mutate(businessId, () => _service.renameZone(zone.id, clean));
  }

  /// Reordena las zonas activas (índices ya ajustados por `onReorderItem`),
  /// optimista. Las inactivas quedan después.
  Future<void> reorderZones(
    String businessId,
    int oldIndex,
    int newIndex,
  ) async {
    final active = [...state.activeZones];
    final moved = active.removeAt(oldIndex);
    active.insert(newIndex, moved);
    final ordered = [...active, ...state.inactiveZones];
    state = state.copyWith(zones: ordered, saving: true, clearError: true);
    try {
      await _service.reorderZones(ordered);
      state = state.copyWith(
        saving: false,
        zones: [
          for (var i = 0; i < ordered.length; i++)
            ordered[i].copyWith(sortIndex: (i + 1) * 10),
        ],
      );
    } catch (e) {
      state = state.copyWith(
        saving: false,
        error: 'No se pudo guardar el orden: $e',
      );
      await load(businessId);
    }
  }

  Future<({FloorDeleteOutcome? outcome, String? error})> deleteZone(
    String businessId,
    FloorZone zone,
  ) {
    return _mutateWithOutcome(businessId, () => _service.deleteZone(zone.id));
  }

  Future<String?> reactivateZone(String businessId, FloorZone zone) {
    return _mutate(businessId, () => _service.reactivateZone(zone.id));
  }

  // ── Mesas ──

  Future<String?> createTable(
    String businessId, {
    required String zoneId,
    required String code,
    String? label,
    required int capacity,
  }) {
    final validation = _validateTable(
      zoneId: zoneId,
      code: code,
      capacity: capacity,
    );
    if (validation != null) return Future.value(validation);
    return _mutate(businessId, () {
      return _service.createTable(
        zoneId: zoneId,
        code: code.trim(),
        label: label?.trim(),
        capacity: capacity,
      );
    });
  }

  /// Crea varias mesas `prefijo + número`. Devuelve el resumen o un error.
  Future<({int created, int skipped, String? error})> createTablesBulk(
    String businessId, {
    required String zoneId,
    required String prefix,
    required int from,
    required int to,
    required int capacity,
  }) async {
    final cleanPrefix = prefix.trim();
    String? error;
    if (cleanPrefix.isEmpty) {
      error = 'Escribe el prefijo (ej. T o Mesa ).';
    } else if (from < 1 || to < from) {
      error =
          'Rango inválido: "desde" debe ser 1 o más y "hasta" no puede ser menor.';
    } else if (to - from + 1 > 200) {
      error = 'Máximo 200 mesas a la vez.';
    } else if (capacity < 1 || capacity > 50) {
      error = 'Las personas por mesa deben estar entre 1 y 50.';
    }
    if (error != null) return (created: 0, skipped: 0, error: error);

    final existing = state.tables
        .where((t) => t.zoneId == zoneId)
        .map((t) => t.code.toLowerCase())
        .toSet();
    state = state.copyWith(saving: true, clearError: true);
    try {
      final result = await _service.createTablesBulk(
        zoneId: zoneId,
        codes: [
          for (var n = from; n <= to; n++) bulkTableCode(cleanPrefix, n, to),
        ],
        capacity: capacity,
        existingCodes: existing,
      );
      state = state.copyWith(saving: false);
      await load(businessId);
      return (created: result.created, skipped: result.skipped, error: null);
    } catch (e) {
      state = state.copyWith(saving: false);
      return (created: 0, skipped: 0, error: e.toString());
    }
  }

  /// Edita una mesa y, si cambió la zona, la mueve (sin tocar sus cuentas).
  Future<String?> updateTable(
    String businessId,
    FloorTable table, {
    required String code,
    String? label,
    required int capacity,
    required String zoneId,
  }) {
    final validation = _validateTable(
      zoneId: zoneId,
      code: code,
      capacity: capacity,
      ignoreTableId: table.id,
    );
    if (validation != null) return Future.value(validation);
    return _mutate(businessId, () async {
      // Mover primero: si el código choca en la zona destino falla antes de
      // cambiar nada más.
      if (zoneId != table.zoneId) {
        await _service.moveTable(tableId: table.id, targetZoneId: zoneId);
      }
      await _service.updateTable(
        tableId: table.id,
        code: code.trim(),
        label: label?.trim(),
        capacity: capacity,
      );
    });
  }

  Future<({FloorDeleteOutcome? outcome, String? error})> deleteTable(
    String businessId,
    FloorTable table,
  ) {
    return _mutateWithOutcome(businessId, () => _service.deleteTable(table.id));
  }

  Future<String?> reactivateTable(String businessId, FloorTable table) {
    return _mutate(businessId, () => _service.reactivateTable(table.id));
  }

  /// Código obligatorio y único en la zona (la base también lo exige, con
  /// mesas inactivas incluidas); personas entre 1 y 50 (igual que el POS).
  String? _validateTable({
    required String zoneId,
    required String code,
    required int capacity,
    String? ignoreTableId,
  }) {
    final clean = code.trim();
    if (clean.isEmpty) return 'Escribe el código de la mesa.';
    if (capacity < 1 || capacity > 50) {
      return 'Las personas por mesa deben estar entre 1 y 50.';
    }
    for (final t in state.tables) {
      if (t.zoneId == zoneId &&
          t.id != ignoreTableId &&
          t.code.toLowerCase() == clean.toLowerCase()) {
        return t.isActive
            ? 'Ya existe la mesa "$clean" en esta zona.'
            : 'Ya existe la mesa "$clean" en esta zona (desactivada): reactívala en vez de crearla.';
      }
    }
    return null;
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
      // Lo que alcanzó a guardarse antes del error se ve igual.
      await load(businessId);
      return e.toString();
    }
  }

  Future<({FloorDeleteOutcome? outcome, String? error})> _mutateWithOutcome(
    String businessId,
    Future<FloorDeleteOutcome> Function() op,
  ) async {
    state = state.copyWith(saving: true, clearError: true);
    try {
      final outcome = await op();
      state = state.copyWith(saving: false);
      await load(businessId);
      return (outcome: outcome, error: null);
    } catch (e) {
      state = state.copyWith(saving: false);
      return (outcome: null, error: e.toString());
    }
  }
}

final floorAdminViewModelProvider =
    StateNotifierProvider<FloorAdminViewModel, FloorAdminState>(
      (ref) => FloorAdminViewModel(ref),
    );
