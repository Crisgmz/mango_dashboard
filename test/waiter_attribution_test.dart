import 'package:flutter_test/flutter_test.dart';
import 'package:mango_dashboard/data/dashboard/waiter_attribution_aggregator.dart';

Map<String, dynamic> _order(
  String id, {
  String? openedByEmployee,
  String? waiterUser,
  String? openedBy,
}) =>
    {
      'id': id,
      'table_sessions': {
        'id': 's-$id',
        'opened_by_employee_id': openedByEmployee,
        'waiter_user_id': waiterUser,
        'opened_by': openedBy,
      },
    };

Map<String, dynamic> _item(
  String orderId, {
  String? employee,
  String? checkId,
  double subtotal = 100,
  double tax = 18,
  double discounts = 0,
  String status = 'served',
}) =>
    {
      'order_id': orderId,
      'check_id': checkId,
      'status': status,
      'subtotal': subtotal,
      'tax': tax,
      'discounts': discounts,
      'created_by_employee_id': employee,
    };

Map<String, dynamic> _employee(String id, String first, String last,
        {String? userId}) =>
    {
      'id': id,
      'first_name': first,
      'last_name': last,
      'user_id': userId,
    };

void main() {
  final roster = [
    _employee('e-ana', 'Ana', 'Reyes'),
    _employee('e-luis', 'Luis', 'Gómez'),
    // El cajero que abre el sistema también es empleado.
    _employee('e-caja', 'Caja', 'Principal', userId: 'u-caja'),
  ];

  test('el PIN de la línea gana sobre el usuario que abrió el sistema', () {
    final result = aggregateWaiterAttribution(
      // La mesa la abrió el cajero (u-caja) en el dispositivo.
      orderRows: [_order('o1', waiterUser: 'u-caja', openedBy: 'u-caja')],
      // Pero quien digitó fue Ana con su PIN.
      itemRows: [_item('o1', employee: 'e-ana')],
      employeeRows: roster,
    );

    expect(result['o1']!.map((w) => w.name), ['Ana Reyes']);
  });

  test('sin PIN en la línea hereda el mesero que abrió la mesa', () {
    final result = aggregateWaiterAttribution(
      orderRows: [
        _order('o1', openedByEmployee: 'e-luis', waiterUser: 'u-caja'),
      ],
      itemRows: [_item('o1')],
      employeeRows: roster,
    );

    expect(result['o1']!.map((w) => w.name), ['Luis Gómez']);
  });

  test('varios meseros en una cuenta: primero el que más digitó', () {
    final result = aggregateWaiterAttribution(
      orderRows: [_order('o1', openedByEmployee: 'e-luis')],
      itemRows: [
        _item('o1', employee: 'e-ana', subtotal: 1000, tax: 180),
        _item('o1', employee: 'e-luis', subtotal: 100, tax: 18),
      ],
      employeeRows: roster,
    );

    expect(result['o1']!.map((w) => w.name), ['Ana Reyes', 'Luis Gómez']);
  });

  test('cuentas divididas se atribuyen por check', () {
    final result = aggregateWaiterAttribution(
      orderRows: [_order('o1')],
      itemRows: [
        _item('o1', employee: 'e-ana', checkId: 'c1'),
        _item('o1', employee: 'e-luis', checkId: 'c2'),
      ],
      employeeRows: roster,
    );

    expect(result['o1::c1']!.map((w) => w.name), ['Ana Reyes']);
    expect(result['o1::c2']!.map((w) => w.name), ['Luis Gómez']);
    expect(result['o1']!.map((w) => w.name).toSet(),
        {'Ana Reyes', 'Luis Gómez'});
  });

  test('ítems anulados no atribuyen', () {
    final result = aggregateWaiterAttribution(
      orderRows: [_order('o1')],
      itemRows: [_item('o1', employee: 'e-ana', status: 'void')],
      employeeRows: roster,
    );

    expect(result['o1'], isNull);
  });

  test('sin PIN en ningún lado cae al usuario de la sesión, ya mapeado a su empleado', () {
    final result = aggregateWaiterAttribution(
      orderRows: [_order('o1', waiterUser: 'u-caja')],
      itemRows: [_item('o1')],
      employeeRows: roster,
    );

    // Mismo id de empleado: la persona no aparece dos veces en el filtro.
    expect(result['o1']!.single.id, 'e-caja');
    expect(result['o1']!.single.name, 'Caja Principal');
  });

  test('usuario sin ficha de empleado usa el nombre resuelto aparte', () {
    final orderRows = [_order('o1', waiterUser: 'u-dueno')];
    final pending =
        waiterUserIdsToResolve(orderRows: orderRows, employeeRows: roster);
    expect(pending, {'u-dueno'});

    final result = aggregateWaiterAttribution(
      orderRows: orderRows,
      itemRows: [_item('o1')],
      employeeRows: roster,
      userNames: const {'u-dueno': 'Cristian Gómez'},
    );

    expect(result['o1']!.single.id, '${waiterUserKeyPrefix}u-dueno');
    expect(result['o1']!.single.name, 'Cristian Gómez');
  });

  test('orden sin ítems conserva el mesero de la sesión', () {
    final result = aggregateWaiterAttribution(
      orderRows: [_order('o1', openedByEmployee: 'e-ana')],
      itemRows: const [],
      employeeRows: roster,
    );

    expect(result['o1']!.single.name, 'Ana Reyes');
  });

  test('sin ninguna atribución la comanda queda sin mesero', () {
    final result = aggregateWaiterAttribution(
      orderRows: [_order('o1')],
      itemRows: [_item('o1')],
      employeeRows: roster,
    );

    expect(result['o1'], isNull);
  });
}
