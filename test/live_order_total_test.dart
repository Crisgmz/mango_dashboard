import 'package:flutter_test/flutter_test.dart';
import 'package:mango_dashboard/data/dashboard/dashboard_data_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Total de una orden en Inicio («Por Cobrar») y en la lista de órdenes: una
/// orden ABIERTA vale solo lo que falta cobrar; una CERRADA, lo que vendió.
void main() {
  final service = DashboardDataService(SupabaseClient('http://localhost', 'test-key'));

  Map<String, dynamic> order({
    String? closedAt,
    required List<Map<String, dynamic>> items,
    List<Map<String, dynamic>> payments = const [],
  }) => {
    'id': 'o1',
    'total': 590,
    'status_ext': closedAt == null ? 'sent_to_kitchen' : 'paid',
    'created_at': '2026-11-10T14:00:00Z',
    'closed_at': closedAt,
    'table_sessions': {
      'id': 's1',
      'dining_tables': {'id': 't1', 'label': 'Mesa 4'},
    },
    'order_items': items,
    'payments': payments,
    'order_checks': const [],
  };

  Map<String, dynamic> item(String status, num subtotal, num tax) => {
    'product_name': 'Producto',
    'qty': 1,
    'subtotal': subtotal,
    'tax': tax,
    'discounts': 0,
    'status': status,
  };

  const paid590 = [
    {'amount': 590, 'change_amount': 0, 'status': 'completed'},
  ];

  test('abierta y cobrada completa: no queda nada por cobrar', () {
    final o = service.mapToLiveOrderItem(
      order(items: [item('paid', 500, 90)], payments: paid590),
    );
    expect(o.total, 0);
  });

  test('abierta con una parte pagada: solo lo que falta', () {
    final o = service.mapToLiveOrderItem(
      order(
        items: [item('paid', 500, 90), item('served', 100, 18)],
        payments: paid590,
      ),
    );
    expect(o.total, closeTo(118, 1e-9));
  });

  test('cerrada: lo que vendió (o lo cobrado si no trae productos)', () {
    expect(
      service
          .mapToLiveOrderItem(
            order(
              closedAt: '2026-11-10T15:00:00Z',
              items: [item('paid', 500, 90)],
              payments: paid590,
            ),
          )
          .total,
      closeTo(590, 1e-9),
    );
    expect(
      service
          .mapToLiveOrderItem(
            order(closedAt: '2026-11-10T15:00:00Z', items: const [], payments: paid590),
          )
          .total,
      closeTo(590, 1e-9),
    );
  });
}
