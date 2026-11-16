import 'package:flutter_test/flutter_test.dart';
import 'package:mango_dashboard/data/dashboard/daily_sales_aggregator.dart';

void main() {
  // Naive (no 'Z') timestamps so day bucketing is timezone-independent in tests.
  // A sale is the payment (sale_scope.dart): it lands on the day it was
  // collected, even if its table is still open.
  final report = aggregateDailySales(
    payRows: [
      {'order_id': 'o1', 'amount': 100, 'change_amount': 0, 'created_at': '2026-05-01T12:00:00'},
      {'order_id': 'o1', 'amount': '50', 'change_amount': '0', 'created_at': '2026-05-01T12:05:00'}, // string parse
      {'order_id': 'o2', 'amount': 200, 'change_amount': 20, 'created_at': '2026-05-01T18:00:00'}, // net 180
      // Open table: one check paid on 05-02, another on 05-03.
      {'order_id': 'o3', 'amount': 300, 'change_amount': 0, 'created_at': '2026-05-02T10:00:00'},
      {'order_id': 'o3', 'amount': 40, 'change_amount': 0, 'created_at': '2026-05-03T10:00:00'},
      {'order_id': '', 'amount': 999, 'change_amount': 0, 'created_at': '2026-05-04T10:00:00'}, // no order → ignored
      {'order_id': 'o5', 'amount': 999, 'change_amount': 0, 'created_at': 'not-a-date'}, // bad date → ignored
    ],
    taxRows: [
      {'tax_name': 'ITBIS', 'tax_rate': 0.18, 'amount': 50},
      {'tax_name': 'ITBIS', 'tax_rate': 0.18, 'amount': '40'}, // string parse
      {'tax_name': 'Propina', 'tax_rate': 0, 'amount': 30}, // rate 0 → null
      {'tax_name': '  ', 'tax_rate': 0.18, 'amount': 5}, // blank name → ignored
    ],
  );

  test('counts distinct orders with a valid sale payment', () {
    expect(report.orderCount, 3); // o1, o2, o3 (o3 once, paid on two days)
  });

  test('gross total = payments net of change, invalid rows ignored', () {
    // 100 + 50 + (200-20) + 300 + 40 = 670
    expect(report.grossTotal, closeTo(670, 1e-9));
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
    expect(report.days[2].total, closeTo(40, 1e-9)); // second check, next day
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
    expect(report.netTotal, closeTo(550, 1e-9)); // 670 − 120
  });

  test('empty input yields an empty, zeroed report', () {
    final empty = aggregateDailySales(payRows: [], taxRows: []);
    expect(empty.days, isEmpty);
    expect(empty.taxes, isEmpty);
    expect(empty.grossTotal, 0);
    expect(empty.orderCount, 0);
    expect(empty.netTotal, 0);
  });
}
