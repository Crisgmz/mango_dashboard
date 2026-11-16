import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mango_dashboard/app/di/providers.dart';
import 'package:mango_dashboard/data/settings/sales_note_settings_service.dart';
import 'package:mango_dashboard/presentation/dashboard/widgets/sales_note_settings_card.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// La nota de venta se enciende solo desde el dashboard (16-nov-2026).

final _client = SupabaseClient(
  'http://localhost:54321',
  'test-key',
  authOptions: const AuthClientOptions(autoRefreshToken: false),
);

class _FakeService extends SalesNoteSettingsService {
  _FakeService(this.stored) : super(_client);

  SalesNoteSettings stored;
  bool failSave = false;
  final saves = <SalesNoteSettings>[];

  @override
  Future<SalesNoteSettings> load(String businessId) async => stored;

  @override
  Future<void> save(String businessId, SalesNoteSettings settings) async {
    saves.add(settings);
    if (failSave) throw Exception('sin red');
    stored = settings;
  }
}

Future<void> _pump(WidgetTester tester, _FakeService service) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [salesNoteSettingsServiceProvider.overrideWithValue(service)],
      child: const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(child: SalesNoteSettingsCard(businessId: 'b1')),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('SalesNoteSettings', () {
    test('prefijo: mayúsculas, sin espacios, tope 6, vacío vuelve a NV-', () {
      expect(SalesNoteSettings.normalizePrefix('nota-'), 'NOTA-');
      expect(SalesNoteSettings.normalizePrefix(' n v - '), 'NV-');
      expect(SalesNoteSettings.normalizePrefix('ABCDEFGH'), 'ABCDEF');
      expect(SalesNoteSettings.normalizePrefix(''), 'NV-');
      expect(SalesNoteSettings.normalizePrefix(null), 'NV-');
    });

    test('sin fila o sin columnas queda apagada con NV-', () {
      final s = SalesNoteSettings.fromRow(null);
      expect(s.enabled, isFalse);
      expect(s.prefix, 'NV-');
      expect(SalesNoteSettings.fromRow({'sales_note_enabled': true, 'sales_note_prefix': 'nt-'}).prefix, 'NT-');
    });

    test('guardar escribe solo las columnas de la nota de venta', () {
      final row = SalesNoteSettingsService.saveRow(
        'b1',
        const SalesNoteSettings(enabled: true, prefix: 'nota-'),
      );
      expect(row, {'business_id': 'b1', 'sales_note_enabled': true, 'sales_note_prefix': 'NOTA-'});
    });
  });

  testWidgets('encender guarda y muestra el prefijo', (tester) async {
    final service = _FakeService(SalesNoteSettings.disabled);
    await _pump(tester, service);

    expect(find.text('Vender por nota de venta'), findsOneWidget);
    expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
    expect(find.text('Prefijo de la numeración'), findsNothing);

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();

    expect(service.saves.single.enabled, isTrue);
    expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);
    expect(find.text('Prefijo de la numeración'), findsOneWidget);
    expect(find.text('Nota de venta encendida.'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'nota-');
    await tester.tap(find.byTooltip('Guardar prefijo'));
    await tester.pumpAndSettle();
    expect(service.saves.last, isA<SalesNoteSettings>());
    expect(service.saves.last.prefix, 'NOTA-');
    expect(service.saves.last.enabled, isTrue);
  });

  testWidgets('si no se guarda, el switch vuelve a como estaba', (tester) async {
    final service = _FakeService(SalesNoteSettings.disabled)..failSave = true;
    await _pump(tester, service);

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();

    expect(service.saves, hasLength(1));
    expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
    expect(find.textContaining('No se pudo guardar'), findsOneWidget);
  });

  testWidgets('el mismo prefijo no vuelve a guardar', (tester) async {
    final service = _FakeService(const SalesNoteSettings(enabled: true, prefix: 'NV-'));
    await _pump(tester, service);

    await tester.enterText(find.byType(TextField), 'nv-');
    await tester.tap(find.byTooltip('Guardar prefijo'));
    await tester.pumpAndSettle();
    expect(service.saves, isEmpty);
  });
}
