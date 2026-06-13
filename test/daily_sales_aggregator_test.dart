import 'package:flutter_test/flutter_test.dart';
import 'package:mango_dashboard/data/dashboard/daily_sales_aggregator.dart';

void main() {
  // Naive (no 'Z') timestamps so day bucketing is timezone-independent in tests.
  final report = aggregateDailySales(
    orderRows: [
      {'id': 'o1', 'closed_at': '2026-05-01T12:00:00'},
      {'id': 'o2', 'closed_at': '2026-05-01T18:00:00'},
      {'id': 'o3', 'closed_at': '2026-05-02T10:00:00'},
      {'id': 'o4', 'closed_at': '2026-05-03T10:00:00'}, // no payment
      {'id': '', 'closed_at': '2026-05-04T10:00:00'}, // bad id → ignored
      {'id': 'o5', 'closed_at': 'not-a-date'}, // bad date → ignored
    ],
    payRows: [
      {'order_id': 'o1', 'amount': 100, 'change_amount': 0},
      {'order_id': 'o1', 'amount': '50', 'change_amount': '0'}, // string parse
      {'order_id': 'o2', 'amount': 200, 'change_amount': 20}, // net 180
      {'order_id': 'o3', 'amount': 300, 'change_amount': 0},
      {'order_id': 'zzz', 'amount': 999, 'change_amount': 0}, // unknown → ignored
    ],
    taxRows: [
      {'tax_name': 'ITBIS', 'tax_rate': 0.18, 'amount': 50},
      {'tax_name': 'ITBIS', 'tax_rate': 0.18, 'amount': '40'}, // string parse
      {'tax_name': 'Propina', 'tax_rate': 0, 'amount': 30}, // rate 0 → null
      {'tax_name': '  ', 'tax_rate': 0.18, 'amount': 5}, // blank name → ignored
    ],
  );

  test('counts only orders with a valid id and date', () {
    expect(report.orderCount, 4); // o1..o4
  });

  test('gross total = payments net of change, unknown orders ignored', () {
    // 100 + 50 + (200-20) + 300 = 630
    expect(report.grossTotal, closeTo(630, 1e-9));
  });

  test('per-day totals are bucketed by local calendar day and sorted', () {
    expect(report.days.map((d) => d.date).toList(), [
      DateTime(2026, 5, 1),
      DateTime(2026, 5, 2),
      DateTime(2026, 5, 3),
    ]);
    expect(report.days[0].orderCount, 2);
    expect(report.days[0].total, closeTo(330, 1e-9)); // 100+50+180
    expect(report.days[1].total, closeTo(300, 1e-9));
    expect(report.days[2].total, closeTo(0, 1e-9)); // counted, but unpaid
    expect(report.days[2].orderCount, 1);
  });

  test('taxes aggregate by name, sorted desc, with average rate', () {
    expect(report.taxes.map((t) => t.name).toList(), ['ITBIS', 'Propina']);
    expect(report.taxes[0].amount, closeTo(90, 1e-9)); // 50 + 40
    expect(report.taxes[0].rate, closeTo(0.18, 1e-9));
    expect(report.taxes[1].amount, closeTo(30, 1e-9));
    expect(report.taxes[1].rate, isNull); // only rate-0 lines → no rate
  });

  test('netTotal = grossTotal − Σ taxes', () {
    expect(report.taxTotal, closeTo(120, 1e-9));
    expect(report.netTotal, closeTo(510, 1e-9)); // 630 − 120
  });

  test('empty input yields an empty, zeroed report', () {
    final empty = aggregateDailySales(orderRows: [], payRows: [], taxRows: []);
    expect(empty.days, isEmpty);
    expect(empty.taxes, isEmpty);
    expect(empty.grossTotal, 0);
    expect(empty.orderCount, 0);
    expect(empty.netTotal, 0);
  });
}
