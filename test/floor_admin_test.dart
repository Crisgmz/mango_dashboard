import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mango_dashboard/app/di/providers.dart';
import 'package:mango_dashboard/core/ids/uuid_v4.dart';
import 'package:mango_dashboard/data/floor/floor_admin_service.dart';
import 'package:mango_dashboard/domain/catalog/product_category.dart';
import 'package:mango_dashboard/domain/floor/floor_models.dart';
import 'package:mango_dashboard/presentation/floor/viewmodel/floor_admin_view_model.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Servicio falso: devuelve el salón fijo y anota las llamadas.
class _FakeFloorService extends FloorAdminService {
  _FakeFloorService(this.zones, this.tables)
    : super(SupabaseClient('http://localhost:54321', 'test-key'));

  final List<FloorZone> zones;
  final List<FloorTable> tables;
  final calls = <String>[];
  List<String>? bulkCodes;
  Set<String>? bulkExisting;

  @override
  Future<({List<FloorZone> zones, List<FloorTable> tables})> loadFloor(
    String businessId,
  ) async => (zones: zones, tables: tables);

  @override
  Future<void> createTable({
    required String zoneId,
    required String code,
    String? label,
    required int capacity,
  }) async => calls.add('create:$zoneId:$code:$capacity');

  @override
  Future<({int created, int skipped})> createTablesBulk({
    required String zoneId,
    required List<String> codes,
    required int capacity,
    required Set<String> existingCodes,
  }) async {
    bulkCodes = codes;
    bulkExisting = existingCodes;
    final created = codes.where(
      (c) => !existingCodes.contains(c.toLowerCase()),
    );
    return (created: created.length, skipped: codes.length - created.length);
  }

  @override
  Future<void> moveTable({
    required String tableId,
    required String targetZoneId,
  }) async => calls.add('move:$tableId:$targetZoneId');

  @override
  Future<void> updateTable({
    required String tableId,
    required String code,
    String? label,
    required int capacity,
  }) async => calls.add('update:$tableId:$code');
}

void main() {
  group('orden y códigos', () {
    test('naturalCompare ordena T2 antes que T10', () {
      final codes = ['T10', 'T2', 'Barra', 't1', 'T02B'];
      codes.sort(naturalCompare);
      expect(codes, ['Barra', 't1', 'T2', 'T02B', 'T10']);
    });

    test('bulkTableCode rellena al largo del "hasta" (mínimo 2)', () {
      expect(bulkTableCode('T', 1, 9), 'T01');
      expect(bulkTableCode('T', 7, 20), 'T07');
      expect(bulkTableCode('Mesa ', 5, 150), 'Mesa005');
      expect(bulkTableCode(' T ', 12, 12), 'T12');
    });
  });

  test('zonas virtuales de venta manual/rápida se reconocen', () {
    expect(
      FloorAdminService.isVirtualSalesZone(
        const FloorZone(id: 'a', name: 'Ventas rápidas', sortIndex: 901),
      ),
      isTrue,
    );
    expect(
      FloorAdminService.isVirtualSalesZone(
        const FloorZone(id: 'b', name: 'Ventas  Manuales', sortIndex: 900),
      ),
      isTrue,
    );
    expect(
      FloorAdminService.isVirtualSalesZone(
        const FloorZone(id: 'c', name: 'Ventas rápidas', sortIndex: 10),
      ),
      isFalse,
      reason: 'una zona normal con ese nombre no es virtual',
    );
  });

  test('uuidV4 tiene formato RFC 4122 v4 y no se repite', () {
    final re = RegExp(
      r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
    );
    final ids = List.generate(200, (_) => uuidV4());
    expect(ids.every(re.hasMatch), isTrue);
    expect(ids.toSet().length, ids.length);
  });

  test('modelos leen las columnas del POS', () {
    final c = ProductCategory.fromJson({
      'id': '1',
      'name': 'Bebidas',
      'position': 20,
      'is_active': false,
      'color': ' ',
    });
    expect([c.position, c.isActive, c.color], [20, false, null]);
    final t = FloorTable.fromJson({
      'id': 't',
      'zone_id': 'z',
      'code': 'T5',
      'label': 'T5',
      'state': 'occupied',
    });
    expect(
      [t.displayName, t.isAvailable, t.stateLabel, t.capacity],
      ['T5', false, 'Ocupada', 4],
    );
    expect(
      const FloorTable(
        id: 'x',
        zoneId: 'z',
        code: 'T1',
        label: ' ',
      ).displayName,
      'T1',
    );
  });

  group('FloorAdminViewModel', () {
    const salon = FloorZone(id: 'z1', name: 'Salón', sortIndex: 10);
    const terraza = FloorZone(id: 'z2', name: 'Terraza', sortIndex: 20);
    final tables = [
      const FloorTable(id: 't1', zoneId: 'z1', code: 'T10'),
      const FloorTable(id: 't2', zoneId: 'z1', code: 'T2'),
      const FloorTable(id: 't3', zoneId: 'z1', code: 'T3', isActive: false),
      const FloorTable(id: 't4', zoneId: 'z2', code: 'T2'),
    ];

    late _FakeFloorService service;
    late ProviderContainer container;
    late FloorAdminViewModel vm;

    setUp(() async {
      service = _FakeFloorService([salon, terraza], tables);
      container = ProviderContainer(
        overrides: [floorAdminServiceProvider.overrideWithValue(service)],
      );
      vm = container.read(floorAdminViewModelProvider.notifier);
      await vm.load('biz');
    });
    tearDown(() => container.dispose());

    test('tablesOf separa activas/inactivas y ordena natural', () {
      final state = container.read(floorAdminViewModelProvider);
      expect(state.tablesOf('z1', active: true).map((t) => t.code), [
        'T2',
        'T10',
      ]);
      expect(state.tablesOf('z1', active: false).map((t) => t.code), ['T3']);
    });

    test(
      'código repetido (aunque esté desactivada) no llega a la base',
      () async {
        final dup = await vm.createTable(
          'biz',
          zoneId: 'z1',
          code: 't2',
          capacity: 4,
        );
        expect(dup, contains('Ya existe la mesa'));
        final inactive = await vm.createTable(
          'biz',
          zoneId: 'z1',
          code: 'T3',
          capacity: 4,
        );
        expect(inactive, contains('reactívala'));
        final badCapacity = await vm.createTable(
          'biz',
          zoneId: 'z1',
          code: 'T9',
          capacity: 0,
        );
        expect(badCapacity, contains('entre 1 y 50'));
        expect(service.calls, isEmpty);

        final ok = await vm.createTable(
          'biz',
          zoneId: 'z1',
          code: ' T9 ',
          capacity: 6,
        );
        expect(ok, isNull);
        expect(service.calls, ['create:z1:T9:6']);
      },
    );

    test('mover a una zona donde el código existe se rechaza antes', () async {
      final error = await vm.updateTable(
        'biz',
        tables[1],
        code: 'T2',
        capacity: 4,
        zoneId: 'z2',
      );
      expect(error, contains('Ya existe la mesa'));
      expect(service.calls, isEmpty);
    });

    test('mover de zona: primero mueve, luego guarda', () async {
      final error = await vm.updateTable(
        'biz',
        tables[0],
        code: 'T10',
        label: 'Terraza 10',
        capacity: 4,
        zoneId: 'z2',
      );
      expect(error, isNull);
      expect(service.calls, ['move:t1:z2', 'update:t1:T10']);
    });

    test('crear varias: códigos con relleno y salta los existentes', () async {
      final result = await vm.createTablesBulk(
        'biz',
        zoneId: 'z1',
        prefix: 'T',
        from: 1,
        to: 12,
        capacity: 4,
      );
      expect(result.error, isNull);
      expect(service.bulkCodes!.first, 'T01');
      expect(service.bulkCodes!.last, 'T12');
      expect(service.bulkExisting, {'t10', 't2', 't3'});
      expect((result.created, result.skipped), (11, 1));
    });

    test('crear varias: rango inválido no llega a la base', () async {
      final result = await vm.createTablesBulk(
        'biz',
        zoneId: 'z1',
        prefix: 'T',
        from: 5,
        to: 2,
        capacity: 4,
      );
      expect(result.error, contains('Rango inválido'));
      expect(service.bulkCodes, isNull);
    });
  });
}
