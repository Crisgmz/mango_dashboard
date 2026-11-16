import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mango_dashboard/app/di/providers.dart';
import 'package:mango_dashboard/core/formatters/mango_formatters.dart';
import 'package:mango_dashboard/data/auth/admin_access_service.dart';
import 'package:mango_dashboard/data/history/change_history_service.dart';
import 'package:mango_dashboard/domain/auth/admin_access_profile.dart';
import 'package:mango_dashboard/domain/history/change_history_entry.dart';
import 'package:mango_dashboard/presentation/auth/viewmodel/auth_gate_view_model.dart';
import 'package:mango_dashboard/presentation/history/change_history_text.dart';
import 'package:mango_dashboard/presentation/history/view/change_history_view.dart';
import 'package:mango_dashboard/presentation/theme/theme_data_factory.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Historial de cambios: las frases y los detalles salen de lo que guarda
/// la base (20261013_0001). Los `changes` de aquí son los mismos que produce
/// supabase/tests/change_history_local_test.sh en mangospos.
const _text = HistoryText(money: MangoFormatters.currency);
String historySentence(ChangeHistoryEntry e) => _text.sentence(e);
List<HistoryLine> historyDetails(ChangeHistoryEntry e) => _text.details(e);

void main() {
  ChangeHistoryEntry entry(
    String table,
    String action, {
    String label = '',
    String context = '',
    String actor = 'Ana Dueña',
    Map<String, dynamic> changes = const {},
    String at = '2026-10-13T19:45:00Z',
  }) => ChangeHistoryEntry.fromJson({
    'id': 1,
    'table_name': table,
    'row_id': 'x',
    'action': action,
    'label': label,
    'context': context,
    'actor_name': actor,
    'changed_at': at,
    'changes': changes,
  });

  group('frases', () {
    test('crear, editar y borrar un producto', () {
      expect(
        historySentence(
          entry('menu_items', 'create', label: 'Johnnie Walker 18'),
        ),
        'Ana Dueña creó el producto Johnnie Walker 18',
      );
      expect(
        historySentence(
          entry(
            'menu_items',
            'update',
            label: 'Pollo',
            changes: {
              'price': [300, 350],
            },
          ),
        ),
        'Ana Dueña editó el producto Pollo',
      );
      expect(
        historySentence(entry('categories', 'delete', label: 'Postres')),
        'Ana Dueña borró la categoría Postres',
      );
    });

    test('apagar o prender es «desactivó/activó»', () {
      expect(
        historySentence(
          entry(
            'menu_items',
            'update',
            label: 'Mojito',
            changes: {
              'is_active': [true, false],
            },
          ),
        ),
        'Ana Dueña desactivó el producto Mojito',
      );
      expect(
        historySentence(
          entry(
            'taxes',
            'update',
            label: 'Ley 10%',
            changes: {
              'is_active': [false, true],
            },
          ),
        ),
        'Ana Dueña activó el impuesto Ley 10%',
      );
    });

    test('vínculos: impuesto de un producto y permisos de un rol', () {
      expect(
        historySentence(
          entry(
            'menu_item_taxes',
            'create',
            label: 'Johnnie Walker 18',
            context: 'ITBIS 18%',
          ),
        ),
        'Ana Dueña le puso ITBIS 18% a Johnnie Walker 18',
      );
      expect(
        historySentence(
          entry(
            'menu_item_taxes',
            'delete',
            label: 'Johnnie Walker 18',
            context: 'Ley 10%',
          ),
        ),
        'Ana Dueña le quitó Ley 10% a Johnnie Walker 18',
      );
      expect(
        historySentence(
          entry(
            'role_permissions',
            'update',
            label: 'Cajero',
            context: 'Eliminar ítem',
            changes: {
              'allow': [true, false],
            },
          ),
        ),
        'Ana Dueña le quitó el permiso «Eliminar ítem» al rol Cajero',
      );
      expect(
        historySentence(
          entry(
            'role_permissions',
            'create',
            label: 'Cajero',
            context: 'Aplicar descuento',
            changes: {'allow': true},
          ),
        ),
        'Ana Dueña le dio el permiso «Aplicar descuento» al rol Cajero',
      );
      expect(
        historySentence(
          entry(
            'user_businesses',
            'create',
            label: 'Juan Pérez',
            context: 'cashier',
          ),
        ),
        'Ana Dueña le dio acceso a Juan Pérez como Cajero',
      );
    });

    test('cuentas: producto quitado, venta y pago anulados', () {
      expect(
        historySentence(
          entry(
            'order_items',
            'delete',
            actor: 'Juan Pérez',
            label: 'Don Julio Reposado',
            context: 'MUEBLE16',
          ),
        ),
        'Juan Pérez quitó Don Julio Reposado de MUEBLE16',
      );
      expect(
        historySentence(
          entry(
            'order_items',
            'update',
            label: 'Agua',
            context: '',
            changes: {
              'quantity': [3, 2],
            },
          ),
        ),
        'Ana Dueña bajó la cantidad de Agua en una cuenta',
      );
      expect(
        historySentence(
          entry(
            'orders',
            'void',
            label: 'Mesa 5',
            changes: {'total': 1250, 'paid_total': 1250},
          ),
        ),
        'Ana Dueña anuló la venta de Mesa 5',
      );
      expect(
        historySentence(
          entry(
            'orders',
            'void',
            label: 'Mesa 5',
            changes: {'total': 800, 'items_count': 2},
          ),
        ),
        'Ana Dueña anuló la cuenta de Mesa 5',
      );
      expect(
        historySentence(entry('payments', 'void', label: 'Mesa 5')),
        'Ana Dueña anuló un pago de Mesa 5',
      );
    });

    // 20261020_0004: quién autorizó con su PIN (supabase/tests/
    // change_history_pin_approvers_local_test.sh en mangospos).
    test('con el PIN de quién: producto quitado, cuenta anulada, mesa liberada', () {
      expect(
        historySentence(
          entry(
            'order_items',
            'delete',
            actor: 'María Gómez',
            label: 'Pizza',
            context: 'Mesa 1',
            changes: {'approved_by': 'Luis Admin', 'reason': 'Se equivocó'},
          ),
        ),
        'María Gómez quitó Pizza de Mesa 1 con el PIN de Luis Admin',
      );
      expect(
        historySentence(
          entry(
            'order_items',
            'update',
            actor: 'Juan Pérez',
            label: 'Mojito',
            context: 'Mesa 1',
            changes: {
              'quantity': [3, 2],
              'approved_by': 'Luis Admin',
            },
          ),
        ),
        'Juan Pérez bajó la cantidad de Mojito en Mesa 1 con el PIN de Luis Admin',
      );
      expect(
        historySentence(
          entry(
            'orders',
            'void',
            actor: 'Juan Pérez',
            label: 'Mesa 1',
            changes: {'total': 900, 'items_count': 1, 'approved_by': 'Luis Admin'},
          ),
        ),
        'Juan Pérez anuló la cuenta de Mesa 1 con el PIN de Luis Admin',
      );
      expect(
        historySentence(
          entry(
            'orders',
            'void',
            actor: 'Juan Pérez',
            label: 'Mesa 2',
            changes: {'total': 0, 'items_count': 0, 'approved_by': 'Ana Dueña'},
          ),
        ),
        'Juan Pérez liberó Mesa 2 (sin consumo) con el PIN de Ana Dueña',
      );
      expect(
        historyDetails(
          entry(
            'order_items',
            'delete',
            changes: {'approved_by': 'Luis Admin', 'reason': 'Se equivocó'},
          ),
        ).map((l) => l.field),
        ['Motivo'],
        reason: 'quien autorizó va en la frase, no se repite abajo',
      );
    });

    test('sin nombre ni etiqueta no deja espacios sueltos', () {
      expect(
        historySentence(entry('menu_items', 'create', actor: '')),
        'Alguien creó el producto',
      );
      expect(
        historySentence(entry('business_settings', 'update', actor: 'Sistema')),
        'Sistema cambió la configuración del POS',
      );
    });
  });

  group('detalles', () {
    test('editar: antes → después con dinero, nombres y Sí/No', () {
      final lines = historyDetails(
        entry(
          'menu_items',
          'update',
          changes: {
            'price': [24000.0, 26000.0],
            'category_id': ['Bebidas', 'Postres'],
            'is_active': [true, false],
          },
        ),
      );
      expect(lines.map((l) => '${l.field}|${l.before}|${l.after}').toList(), [
        'Precio|RD\$ 24,000.00|RD\$ 26,000.00',
        'Categoría|Bebidas|Postres',
        'Activo|Sí|No',
      ]);
    });

    test('lo vacío se dice, y un id sin traducir no se muestra crudo', () {
      final lines = historyDetails(
        entry(
          'menu_items',
          'update',
          changes: {
            'image_url': [null, 'imagen nueva'],
            'group_id': ['0b6f8f2c-1111-4c2b-9a51-2f0b8f9d1a10', 'Salsas'],
          },
        ),
      );
      expect(lines.map((l) => '${l.field}|${l.before}|${l.after}').toList(), [
        'Imagen|(vacío)|imagen nueva',
        'Grupo|(sin nombre)|Salsas',
      ]);
    });

    test('crear/borrar: la foto sin ids, sin «No» ni vacíos', () {
      final lines = historyDetails(
        entry(
          'menu_items',
          'delete',
          changes: {
            'name': 'Johnnie Walker 18',
            'price': 29000,
            'is_active': true,
            'has_variants': false,
            'description': '',
            'inventory_item_id': '0b6f8f2c-1111-4c2b-9a51-2f0b8f9d1a10',
          },
        ),
      );
      expect(lines.map((l) => '${l.field}|${l.before}').toList(), [
        'Nombre|Johnnie Walker 18',
        'Precio|RD\$ 29,000.00',
        'Activo|Sí',
      ]);
      expect(lines.every((l) => !l.isChange), isTrue);
    });

    test('vínculos: los ids del vínculo no salen (ya están en la frase)', () {
      final lines = historyDetails(
        entry(
          'role_permissions',
          'update',
          changes: {
            'role_id': 'Cajero',
            'permission_id': 'Eliminar ítem',
            'allow': [true, false],
          },
        ),
      );
      expect(lines.map((l) => '${l.field}|${l.before}|${l.after}').toList(), [
        'Permitido|Sí|No',
      ]);
    });

    test('producto quitado: cantidad antes → después y el motivo', () {
      final lines = historyDetails(
        entry(
          'order_items',
          'update',
          changes: {
            'quantity': [3, 2],
            'unit_price': 500,
            'amount': 500,
            'reason': 'Cliente cambió de idea',
            'kitchen_sent': true,
          },
        ),
      );
      expect(lines.map((l) => '${l.field}|${l.before}|${l.after}').toList(), [
        'Cantidad|3|2',
        'Precio|RD\$ 500.00|null',
        'Monto|RD\$ 500.00|null',
        'Motivo|Cliente cambió de idea|null',
        'Ya había salido a cocina|Sí|null',
      ]);
    });

    test('pago anulado: estado traducido y tasa en %', () {
      final pay = historyDetails(
        entry(
          'payments',
          'void',
          changes: {
            'amount': 600,
            'payment_method': 'Efectivo',
            'status': ['completed', 'cancelled'],
          },
        ),
      );
      expect(pay.map((l) => '${l.field}|${l.before}|${l.after}').toList(), [
        'Monto|RD\$ 600.00|null',
        'Método de pago|Efectivo|null',
        'Estado|Cobrado|Anulado',
      ]);
      final tax = historyDetails(
        entry(
          'taxes',
          'update',
          changes: {
            'rate': [18, 16],
          },
        ),
      );
      expect('${tax.single.before}|${tax.single.after}', '18%|16%');
    });
  });

  group('operaciones (20261013_0002)', () {
    test('caja: entra, sale, gasto, abrir, cerrar', () {
      expect(
        historySentence(
          entry(
            'cash_transactions',
            'create',
            actor: 'Juan Pérez',
            label: 'Caja 1',
            context: 'Fondo para cambio',
            changes: {'event': 'cash_deposit', 'amount': 500},
          ),
        ),
        'Juan Pérez agregó RD\$ 500.00 a Caja 1',
      );
      expect(
        historySentence(
          entry(
            'cash_transactions',
            'create',
            label: 'Caja 1',
            changes: {'event': 'cash_withdrawal', 'amount': 300},
          ),
        ),
        'Ana Dueña retiró RD\$ 300.00 de Caja 1',
      );
      expect(
        historySentence(
          entry(
            'cash_transactions',
            'update',
            label: 'Caja 1',
            changes: {
              'event': 'cash_deposit',
              'amount': [500, 50],
            },
          ),
        ),
        'Ana Dueña editó una entrada de Caja 1',
      );
      expect(
        historySentence(
          entry(
            'cash_register_sessions',
            'create',
            label: 'Caja 1',
            changes: {'event': 'cash_open', 'start_amount': 2000},
          ),
        ),
        'Ana Dueña abrió Caja 1 con RD\$ 2,000.00',
      );
      expect(
        historySentence(
          entry(
            'cash_register_sessions',
            'update',
            label: 'Caja 1',
            changes: {
              'event': 'cash_force_close',
              'status': ['open', 'closed'],
            },
          ),
        ),
        'Ana Dueña cerró a la fuerza Caja 1',
      );
      final close = historyDetails(
        entry(
          'cash_register_sessions',
          'update',
          changes: {
            'event': 'cash_close',
            'status': ['open', 'closed'],
            'start_amount': 2000,
            'end_amount': 2300,
            'difference': -15,
            'notes': 'Todo bien',
          },
        ),
      );
      expect(close.map((l) => '${l.field}|${l.before}|${l.after}').toList(), [
        'Estado|Abierta|Cerrada',
        'Fondo|RD\$ 2,000.00|null',
        'Contado|RD\$ 2,300.00|null',
        'Diferencia|-RD\$ 15.00|null',
        'Notas|Todo bien|null',
      ]);
    });

    test('cuentas: traslados, descuento y método de pago', () {
      expect(
        historySentence(
          entry(
            'table_sessions',
            'update',
            label: 'Mesa 3',
            context: 'Mesa 1',
            changes: {'event': 'table_transfer'},
          ),
        ),
        'Ana Dueña pasó la cuenta de Mesa 3 a Mesa 1',
      );
      expect(
        historySentence(
          entry(
            'table_sessions',
            'update',
            label: 'Mesa 3',
            context: 'Mesa 1',
            changes: {
              'event': 'items_transfer',
              'items_count': 2,
              'products': ['2 × Mojito', '1 × Nachos'],
            },
          ),
        ),
        'Ana Dueña pasó 2 productos de Mesa 3 a Mesa 1',
      );
      // Las que 0001 anotó como anulación y 0002 corrigió: sin mesa destino.
      expect(
        historySentence(
          entry(
            'table_sessions',
            'update',
            label: 'Mesa 3',
            changes: {'event': 'items_transfer', 'total': 900},
          ),
        ),
        'Ana Dueña pasó la cuenta de Mesa 3 a otra mesa',
      );
      final discount = entry(
        'orders',
        'update',
        label: 'Mesa 2',
        changes: {
          'event': 'discount',
          'discount': [0.0, 90.0],
          'lines': {
            'a': {'name': 'Mojito', 'before': 0, 'after': 60},
            'b': {'name': 'Nachos', 'before': 0, 'after': 30},
          },
        },
      );
      expect(
        historySentence(discount),
        'Ana Dueña aplicó un descuento de RD\$ 90.00 en Mesa 2',
      );
      expect(
        historyDetails(
          discount,
        ).map((l) => '${l.field}|${l.before}|${l.after}').toList(),
        [
          'Descuento total|RD\$ 0.00|RD\$ 90.00',
          'Mojito|RD\$ 0.00|RD\$ 60.00',
          'Nachos|RD\$ 0.00|RD\$ 30.00',
        ],
      );
      expect(
        historySentence(
          entry(
            'orders',
            'update',
            label: 'Mesa 2',
            changes: {'event': 'discount', 'courtesy': 'Cumpleaños'},
          ),
        ),
        'Ana Dueña dio una cortesía en Mesa 2',
      );
      expect(
        historyDetails(
          entry(
            'payments',
            'update',
            changes: {
              'event': 'payment_method',
              'payment_method': ['Efectivo', 'Tarjeta'],
              'amount': 900,
            },
          ),
        ).first.after,
        'Tarjeta',
      );
    });

    test('cocina: un envío con sus productos, uno por línea', () {
      final send = entry(
        'kitchen_rounds',
        'create',
        actor: 'María Gómez',
        label: 'Mesa 3',
        changes: {
          'event': 'kitchen_send',
          'items_count': 2,
          'products': [
            '2 × Hamburguesa + Queso extra (sin cebolla)',
            '1 × Coca-Cola',
          ],
        },
      );
      expect(
        historySentence(send),
        'María Gómez envió 2 productos de Mesa 3 a cocina',
      );
      expect(
        historyDetails(send).map((l) => '${l.field}|${l.before}').toList(),
        ['|2 × Hamburguesa + Queso extra (sin cebolla)', '|1 × Coca-Cola'],
      );
      expect(historyAreaLabel('kitchen_rounds'), 'Cocina');
    });

    test('créditos, compras e inventario', () {
      expect(
        historySentence(
          entry(
            'credit_payments',
            'create',
            label: 'AB-00001',
            context: 'Pedro Cliente',
            changes: {'event': 'abono', 'amount': 400},
          ),
        ),
        'Ana Dueña recibió un abono de RD\$ 400.00 de Pedro Cliente (AB-00001)',
      );
      expect(
        historySentence(
          entry(
            'supplier_credit_payments',
            'create',
            label: 'Distribuidora Vocatus',
            changes: {'event': 'supplier_payment', 'amount': 2000},
          ),
        ),
        'Ana Dueña le pagó RD\$ 2,000.00 a Distribuidora Vocatus',
      );
      expect(
        historySentence(
          entry(
            'purchase_orders',
            'update',
            label: 'PO-12',
            changes: {
              'status': ['draft', 'cancelled'],
            },
          ),
        ),
        'Ana Dueña canceló la orden de compra PO-12',
      );
      expect(
        historySentence(entry('purchase_orders', 'create', label: 'PO-12')),
        'Ana Dueña creó la orden de compra PO-12',
      );
      final out = entry(
        'inventory_movements',
        'create',
        label: 'Ron blanco',
        context: 'Bar',
        changes: {
          'event': 'stock_outflow',
          'quantity': -1,
          'reason_code': 'breakage',
          'destination': 'Basura',
        },
      );
      expect(
        historySentence(out),
        'Ana Dueña registró una salida de Ron blanco',
      );
      expect(
        historyDetails(out).map((l) => '${l.field}|${l.before}').toList(),
        ['Cantidad|-1', 'Motivo|Rotura', 'Destino|Basura'],
      );
      expect(
        historySentence(
          entry(
            'loyalty_stamp_adjustments',
            'create',
            label: 'Pedro Cliente',
            changes: {'event': 'stamps_adjust', 'stamps': -1},
          ),
        ),
        'Ana Dueña le quitó 1 sello a Pedro Cliente',
      );
      expect(
        historySentence(
          entry(
            'device_sessions',
            'update',
            label: 'PC Barra',
            changes: {'event': 'device_revoke'},
          ),
        ),
        'Ana Dueña cerró a distancia la sesión de PC Barra',
      );
    });
  });

  group('fechas', () {
    test('hora en 12 h y días legibles', () {
      expect(historyTime(DateTime(2026, 10, 13, 15, 5)), '3:05 p. m.');
      expect(historyTime(DateTime(2026, 10, 13, 0, 30)), '12:30 a. m.');
      final now = DateTime(2026, 10, 13, 10);
      expect(historyDayLabel(DateTime(2026, 10, 13, 1), now: now), 'Hoy');
      expect(historyDayLabel(DateTime(2026, 10, 12, 23), now: now), 'Ayer');
      expect(
        historyDayLabel(DateTime(2026, 10, 5, 9), now: now),
        'lunes 5 de octubre',
      );
      expect(
        historyDayLabel(DateTime(2025, 12, 31), now: now),
        'miércoles 31 de diciembre de 2025',
      );
    });
  });

  pantalla();
}

// ---------------------------------------------------------------------------
// Pantalla: teléfono, tema claro y oscuro, datos falsos.
// ---------------------------------------------------------------------------

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

class _FakeHistory extends ChangeHistoryService {
  _FakeHistory(this.rows) : super(_client);
  final List<Map<String, dynamic>> rows;
  final calls = <List<String>>[];

  @override
  Future<List<ChangeHistoryEntry>> loadPage({
    required String businessId,
    int offset = 0,
    List<String> tables = const [],
    String? action,
    String search = '',
  }) async {
    calls.add(tables);
    return rows
        .where((r) => tables.isEmpty || tables.contains(r['table_name']))
        .map(ChangeHistoryEntry.fromJson)
        .toList(growable: false);
  }
}

void pantalla() {
  final now = DateTime.now().toUtc();
  String ago(Duration d) => now.subtract(d).toIso8601String();
  final rows = <Map<String, dynamic>>[
    {
      'id': 3,
      'table_name': 'menu_items',
      'row_id': 'p1',
      'action': 'update',
      'label': 'Johnnie Walker 18 años etiqueta negra edición especial',
      'context': '',
      'actor_name': 'Luis Admin',
      'changed_at': ago(const Duration(minutes: 5)),
      'changes': {
        'price': [24000, 26000],
        'category_id': ['Bebidas', 'Licores importados'],
      },
    },
    {
      'id': 2,
      'table_name': 'order_items',
      'row_id': 'i1',
      'action': 'delete',
      'label': 'Don Julio Reposado',
      'context': 'MUEBLE16',
      'actor_name': 'Juan Pérez',
      'changed_at': ago(const Duration(minutes: 30)),
      'changes': {
        'quantity': 1,
        'unit_price': 12000,
        'amount': 12000,
        'reason': 'Cliente cambió de idea',
        'kitchen_sent': true,
      },
    },
    {
      'id': 1,
      'table_name': 'role_permissions',
      'row_id': 'r1:p1',
      'action': 'update',
      'label': 'Cajero',
      'context': 'Eliminar ítem',
      'actor_name': 'Ana Dueña',
      'changed_at': ago(const Duration(days: 1)),
      'changes': {
        'allow': [true, false],
      },
    },
  ];

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

  for (final dark in [false, true]) {
    testWidgets(
      'pantalla: lista, detalles y filtro (${dark ? 'oscuro' : 'claro'})',
      (tester) async {
        final fake = _FakeHistory(rows);
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              adminAccessServiceProvider.overrideWithValue(_FakeAccess()),
              authGateViewModelProvider.overrideWith(_FakeAuthGate.new),
              changeHistoryServiceProvider.overrideWithValue(fake),
            ],
            child: MaterialApp(
              theme: MangoThemeFactory.lightTheme,
              darkTheme: MangoThemeFactory.darkTheme,
              themeMode: dark ? ThemeMode.dark : ThemeMode.light,
              home: const ChangeHistoryView(),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('HOY'), findsOneWidget);
        expect(find.text('AYER'), findsOneWidget);
        expect(
          find.textContaining('Luis Admin editó el producto Johnnie'),
          findsOneWidget,
        );
        // La edición se ve abierta: antes → después.
        expect(
          find.textContaining('Licores importados', findRichText: true),
          findsOneWidget,
        );
        // Lo borrado se abre al tocar.
        expect(
          find.text('Juan Pérez quitó Don Julio Reposado de MUEBLE16'),
          findsOneWidget,
        );
        expect(
          find.textContaining('Cliente cambió de idea', findRichText: true),
          findsNothing,
        );
        await tester.tap(find.text('Ver lo que se borró'));
        await tester.pumpAndSettle();
        expect(
          find.textContaining('Cliente cambió de idea', findRichText: true),
          findsOneWidget,
        );
        expect(find.text('Ocultar detalles'), findsOneWidget);

        // Filtro por área: pide solo esas tablas.
        await tester.tap(find.text('Cuentas'));
        await tester.pumpAndSettle();
        expect(
          fake.calls.last,
          containsAll(['order_items', 'orders', 'payments']),
        );
        expect(find.textContaining('Luis Admin'), findsNothing);
        expect(
          find.text('Juan Pérez quitó Don Julio Reposado de MUEBLE16'),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
}
