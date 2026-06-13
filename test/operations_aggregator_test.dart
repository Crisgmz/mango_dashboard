import 'package:flutter_test/flutter_test.dart';
import 'package:mango_dashboard/data/dashboard/operations_aggregator.dart';
import 'package:mango_dashboard/domain/dashboard/dashboard_models.dart';

Map<String, dynamic> _order(
  String id, {
  required String sid,
  String? zone,
  String? table,
  required String origin,
  String? opened,
  String? closed,
  int? people,
}) =>
    {
      'id': id,
      'table_sessions': {
        'id': sid,
        'opened_at': opened,
        'closed_at': closed,
        'people_count': people,
        'origin': origin,
        'dining_tables': table == null
            ? null
            : {
                'name': table,
                'zones': zone == null ? null : {'name': zone},
              },
      },
    };

double _byName(List<NamedSales> xs, String name) =>
    xs.firstWhere((x) => x.name == name).total;
int _ordersOf(List<NamedSales> xs, String name) =>
    xs.firstWhere((x) => x.name == name).orderCount;

void main() {
  final report = aggregateOperations(
    orderRows: [
      _order('o1',
          sid: 's1',
          zone: 'Terraza',
          table: 'Mesa 1',
          origin: 'dine_in',
          opened: '2026-05-01T18:00:00Z',
          closed: '2026-05-01T19:12:00Z', // 72 min
          people: 4),
      // Same session s1 (second order on the same table) — must NOT double-count
      // the session, its covers, or its turnover.
      _order('o2',
          sid: 's1',
          zone: 'Terraza',
          table: 'Mesa 1',
          origin: 'dine_in',
          opened: '2026-05-01T18:00:00Z',
          closed: '2026-05-01T19:12:00Z',
          people: 4),
      _order('o3',
          sid: 's2',
          zone: 'Salón',
          table: 'Mesa 5',
          origin: 'dine_in',
          opened: '2026-05-01T20:00:00Z',
          closed: '2026-05-01T21:00:00Z', // 60 min
          people: 2),
      _order('o4', sid: 's3', origin: 'delivery'), // no table/zone/covers/times
      _order('', sid: 'sx', origin: 'dine_in'), // invalid id → ignored
    ],
    payRows: [
      {'order_id': 'o1', 'amount': 500, 'change_amount': 0},
      {'order_id': 'o2', 'amount': 300, 'change_amount': 0},
      {'order_id': 'o3', 'amount': 400, 'change_amount': 0},
      {'order_id': 'o4', 'amount': 250, 'change_amount': 0},
      {'order_id': 'zz', 'amount': 999, 'change_amount': 0}, // unknown → ignored
    ],
  );

  test('totals, distinct orders and sessions', () {
    expect(report.totalSales, closeTo(1450, 1e-9));
    expect(report.orderCount, 4); // o1..o4
    expect(report.sessionCount, 3); // s1, s2, s3
  });

  test('sales by zone (sorted desc), with a "Sin zona" bucket for delivery', () {
    expect(report.zones.first.name, 'Terraza');
    expect(_byName(report.zones, 'Terraza'), closeTo(800, 1e-9)); // 500 + 300
    expect(_ordersOf(report.zones, 'Terraza'), 2);
    expect(_byName(report.zones, 'Salón'), closeTo(400, 1e-9));
    expect(_byName(report.zones, 'Sin zona'), closeTo(250, 1e-9));
  });

  test('sales by origin', () {
    expect(_byName(report.origins, 'dine_in'), closeTo(1200, 1e-9));
    expect(_ordersOf(report.origins, 'dine_in'), 3);
    expect(_byName(report.origins, 'delivery'), closeTo(250, 1e-9));
  });

  test('turnover averages only closed sessions, counted once', () {
    // s1 = 72 min, s2 = 60 min, s3 = no times → (72 + 60) / 2
    expect(report.avgTurnoverMinutes, closeTo(66, 1e-9));
  });

  test('covers counted once per session; ticket per person', () {
    expect(report.totalCovers, 6); // 4 (s1, once) + 2 (s2); s3 unknown
    expect(report.ticketPerPerson, closeTo(1450 / 6, 1e-9));
  });

  test('empty input is zeroed', () {
    final empty = aggregateOperations(orderRows: const [], payRows: const []);
    expect(empty.totalSales, 0);
    expect(empty.sessionCount, 0);
    expect(empty.zones, isEmpty);
    expect(empty.avgTurnoverMinutes, 0);
    expect(empty.ticketPerPerson, 0);
  });
}
