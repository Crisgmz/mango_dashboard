import 'package:flutter_test/flutter_test.dart';
import 'package:mango_dashboard/data/dashboard/sale_scope.dart';

/// Regla de «venta» (2026-11-10, GFC mesa GR3): una subcuenta pagada cuenta
/// cuando se paga, aunque la mesa siga abierta con otra pendiente.
void main() {
  final start = DateTime.utc(2026, 11, 10, 9); // 5 AM RD
  final end = DateTime.utc(2026, 11, 11, 9);

  Map<String, dynamic> item({
    String status = 'paid',
    Map<String, dynamic>? check,
    String? orderClosedAt,
    String orderStatus = 'sent_to_kitchen',
  }) => {
    'status': status,
    'order_checks': check,
    'orders': {'status_ext': orderStatus, 'closed_at': orderClosedAt},
  };

  test('subcuenta pagada con la mesa abierta: vendida cuando se pagó', () {
    final i = item(check: {'is_closed': true, 'closed_at': '2026-11-10T18:12:40Z'});
    expect(itemSoldAt(i), DateTime.utc(2026, 11, 10, 18, 12, 40));
    expect(itemSoldInRange(i, start, end), isTrue);
  });

  test('subcuenta pendiente con la mesa abierta: todavía no se vendió', () {
    final i = item(status: 'pending', check: {'is_closed': false, 'closed_at': null});
    expect(itemSoldAt(i), isNull);
    expect(itemSoldInRange(i, start, end), isFalse);
  });

  test('sin subcuenta: se vende al cerrarse la orden', () {
    expect(itemSoldInRange(item(orderClosedAt: '2026-11-10T16:29:10Z'), start, end), isTrue);
    expect(itemSoldInRange(item(orderClosedAt: '2026-11-09T16:29:10Z'), start, end), isFalse,
        reason: 'cerrada ayer: es venta de ayer');
  });

  test('subcuenta pagada ayer y mesa cerrada hoy: la línea es de ayer (una sola vez)', () {
    final i = item(
      check: {'is_closed': true, 'closed_at': '2026-11-09T22:00:00Z'},
      orderClosedAt: '2026-11-10T15:00:00Z',
    );
    expect(itemSoldInRange(i, start, end), isFalse);
  });

  test('anulada (la línea o la orden): nunca es venta', () {
    expect(itemSoldAt(item(status: 'void', orderClosedAt: '2026-11-10T16:00:00Z')), isNull);
    expect(itemSoldAt(item(orderStatus: 'void', orderClosedAt: '2026-11-10T16:00:00Z')), isNull);
  });
}
