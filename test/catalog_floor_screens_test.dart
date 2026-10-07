import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mango_dashboard/app/di/providers.dart';
import 'package:mango_dashboard/data/auth/admin_access_service.dart';
import 'package:mango_dashboard/data/catalog/catalog_admin_service.dart';
import 'package:mango_dashboard/data/floor/floor_admin_service.dart';
import 'package:mango_dashboard/domain/auth/admin_access_profile.dart';
import 'package:mango_dashboard/domain/catalog/product_category.dart';
import 'package:mango_dashboard/domain/floor/floor_models.dart';
import 'package:mango_dashboard/presentation/auth/viewmodel/auth_gate_view_model.dart';
import 'package:mango_dashboard/presentation/catalog/view/categories_admin_view.dart';
import 'package:mango_dashboard/presentation/floor/view/floor_admin_view.dart';
import 'package:mango_dashboard/presentation/theme/theme_data_factory.dart';
import 'package:mango_dashboard/presentation/widgets/soft_admin_parts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Pinta las pantallas de categorías y salón con datos falsos, en teléfono y
/// en tema claro/oscuro: sin overflows ni errores de layout, y los flujos
/// principales abren lo que deben.

// Sin auto-refresco: su timer periódico quedaría vivo al terminar el test.
final _client = SupabaseClient(
  'http://localhost:54321',
  'test-key',
  authOptions: const AuthClientOptions(autoRefreshToken: false),
);

class _FakeAccess extends AdminAccessService {
  _FakeAccess() : super(_client);
  @override
  Stream<AuthState> authStates() => const Stream.empty();
}

class _FakeAuthGate extends AuthGateViewModel {
  _FakeAuthGate(super.ref) {
    state = const AuthGateState(
      isLoading: false,
      isAuthenticated: true,
      error: null,
      profile: AdminAccessProfile(
        userId: 'u1',
        userName: 'Dueño',
        email: null,
        businessId: 'biz',
        businessName: 'Negocio',
        branchName: null,
        rawRole: 'owner',
        normalizedRole: 'owner',
        allowed: true,
        memberships: [],
      ),
    );
  }
}

class _FakeCatalog extends CatalogAdminService {
  _FakeCatalog(this.categories) : super(_client);
  final List<ProductCategory> categories;

  @override
  Future<({List<ProductCategory> categories, bool supportsColor})>
  loadCategoriesForAdmin(String businessId) async =>
      (categories: categories, supportsColor: true);

  @override
  Future<Map<String, int>> loadCategoryProductCounts(String businessId) async =>
      {for (final c in categories) c.id: 3};
}

class _FakeFloor extends FloorAdminService {
  _FakeFloor(this.zones, this.tables) : super(_client);
  final List<FloorZone> zones;
  final List<FloorTable> tables;

  @override
  Future<({List<FloorZone> zones, List<FloorTable> tables})> loadFloor(
    String businessId,
  ) async => (zones: zones, tables: tables);
}

Widget _app(Widget home, List<Override> overrides, {bool dark = false}) {
  return ProviderScope(
    overrides: [
      adminAccessServiceProvider.overrideWithValue(_FakeAccess()),
      authGateViewModelProvider.overrideWith(_FakeAuthGate.new),
      ...overrides,
    ],
    child: MaterialApp(
      theme: MangoThemeFactory.lightTheme,
      darkTheme: MangoThemeFactory.darkTheme,
      themeMode: dark ? ThemeMode.dark : ThemeMode.light,
      home: home,
    ),
  );
}

void main() {
  setUp(() {
    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    binding.platformDispatcher.views.first.physicalSize = const Size(
      360 * 3,
      780 * 3,
    );
    binding.platformDispatcher.views.first.devicePixelRatio = 3;
  });
  tearDown(() {
    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    binding.platformDispatcher.views.first.resetPhysicalSize();
    binding.platformDispatcher.views.first.resetDevicePixelRatio();
  });

  final categories = [
    const ProductCategory(
      id: 'c1',
      name: 'Bebidas',
      position: 10,
      color: '#3B82F6',
    ),
    const ProductCategory(
      id: 'c2',
      name: 'Platos fuertes con nombre muy largo para probar',
      position: 20,
    ),
    const ProductCategory(
      id: 'c3',
      name: 'Postres',
      position: 30,
      isActive: false,
    ),
  ];
  final zones = [
    const FloorZone(id: 'z1', name: 'Salón principal', sortIndex: 10),
    const FloorZone(id: 'z2', name: 'Terraza', sortIndex: 20),
    const FloorZone(
      id: 'z3',
      name: 'Patio viejo',
      sortIndex: 30,
      isActive: false,
    ),
  ];
  final tables = [
    const FloorTable(id: 't1', zoneId: 'z1', code: 'T10', label: 'T10'),
    const FloorTable(
      id: 't2',
      zoneId: 'z1',
      code: 'T2',
      label: 'Ventana 2',
      capacity: 6,
    ),
    const FloorTable(id: 't3', zoneId: 'z1', code: 'T3', state: 'occupied'),
    const FloorTable(id: 't4', zoneId: 'z1', code: 'T9', isActive: false),
  ];

  for (final dark in [false, true]) {
    final mode = dark ? 'oscuro' : 'claro';

    testWidgets(
      'categorías: lista, interruptor y diálogo con colores ($mode)',
      (tester) async {
        await tester.pumpWidget(
          _app(const CategoriesAdminView(), [
            catalogAdminServiceProvider.overrideWithValue(
              _FakeCatalog(categories),
            ),
          ], dark: dark),
        );
        await tester.pumpAndSettle();

        expect(find.text('Bebidas'), findsOneWidget);
        expect(find.text('3 productos · Oculta en el POS'), findsOneWidget);
        expect(find.byType(Switch), findsNWidgets(3));
        expect(find.text('Nueva categoría'), findsOneWidget);

        await tester.tap(find.text('Bebidas'));
        await tester.pumpAndSettle();
        expect(find.text('Color del botón en el POS'), findsOneWidget);
        // Con productos no ofrece eliminar: explica qué hacer.
        expect(find.text('Eliminar categoría'), findsNothing);
        expect(find.textContaining('Tiene 3 productos'), findsOneWidget);
        await tester.tap(find.text('Cancelar'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('salón: zonas, desactivadas y mesas de una zona ($mode)', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(const FloorAdminView(), [
          floorAdminServiceProvider.overrideWithValue(
            _FakeFloor(zones, tables),
          ),
        ], dark: dark),
      );
      await tester.pumpAndSettle();

      expect(find.text('Salón principal'), findsOneWidget);
      expect(find.text('3 mesas · 1 ocupada'), findsOneWidget);
      expect(
        find.text('Sin mesas'),
        findsNWidgets(2),
      ); // Terraza y la desactivada
      expect(find.text('DESACTIVADAS (1)'), findsOneWidget);
      expect(find.text('Reactivar'), findsOneWidget);

      await tester.tap(find.text('Salón principal'));
      await tester.pumpAndSettle();
      expect(find.text('MESAS (3)'), findsOneWidget);
      // Orden natural: T2 (Ventana 2), T3, T10; luego la desactivada.
      final titles = tester
          .widgetList<SoftRowCard>(find.byType(SoftRowCard))
          .map((c) => c.title)
          .toList();
      expect(titles, ['Ventana 2', 'T3', 'T10', 'T9']);
      expect(find.text('OCUPADA'), findsOneWidget);
      expect(find.text('Código T2 · 6 personas'), findsOneWidget);

      // Mesa ocupada: el diálogo no ofrece eliminar y explica por qué.
      await tester.tap(
        find.byWidgetPredicate((w) => w is SoftRowCard && w.title == 'T3'),
      );
      await tester.pumpAndSettle();
      expect(find.text('Eliminar mesa'), findsNothing);
      expect(find.textContaining('libérala en el POS'), findsOneWidget);
      expect(find.text('Zona'), findsOneWidget);
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();

      // Crear varias: vista previa con relleno.
      await tester.tap(find.text('Varias'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Se crearán 10 mesas: T01 … T10'),
        findsOneWidget,
      );
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('salón vacío ($mode)', (tester) async {
      await tester.pumpWidget(
        _app(const FloorAdminView(), [
          floorAdminServiceProvider.overrideWithValue(
            _FakeFloor(const [], const []),
          ),
        ], dark: dark),
      );
      await tester.pumpAndSettle();
      expect(find.text('Aún no hay zonas'), findsOneWidget);
      expect(find.text('Crear zona'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('categorías vacías ($mode)', (tester) async {
      await tester.pumpWidget(
        _app(const CategoriesAdminView(), [
          catalogAdminServiceProvider.overrideWithValue(_FakeCatalog(const [])),
        ], dark: dark),
      );
      await tester.pumpAndSettle();
      expect(find.text('Aún no hay categorías'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
