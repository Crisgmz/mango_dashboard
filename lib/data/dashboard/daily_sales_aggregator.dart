import '../../domain/dashboard/dashboard_models.dart';
import 'tax_lines_aggregator.dart';

/// Pure aggregation for the "Ventas por día" report. Given the sale
/// `payments` (amount, change_amount, order_id, created_at) and the sold
/// `order_item_tax_lines` already fetched for the range (sale_scope.dart),
/// computes per-day gross sales, the range-wide tax breakdown, and totals.
///
/// Kept separate from the Supabase query so the money math is unit-testable:
///  - gross per day = the payments collected that day, net of change (a sale
///    is the payment, not the table closing);
///  - orders per day = distinct orders paid that day;
///  - `netTotal = grossTotal − Σ taxes` (see [DailySalesReport]);
///  - taxes aggregated by name, with the average rate when one is recorded.
DailySalesReport aggregateDailySales({
  required List<Map<String, dynamic>> payRows,
  required List<Map<String, dynamic>> taxRows,
  int cutoffHour = 0,
}) {
  // ── Gross per local OPERATIVE day of the payment ──
  // The business day starts at [cutoffHour] (e.g. 5 AM): a sale at 2 AM
  // belongs to the previous day's bucket, matching the dashboard's Hoy/Ayer.
  final byDay = <DateTime, _DayAgg>{};
  final orders = <String>{};
  double grossTotal = 0;
  for (final row in payRows) {
    final oid = row['order_id']?.toString();
    final paidAt = DateTime.tryParse(row['created_at']?.toString() ?? '');
    if (oid == null || oid.isEmpty || paidAt == null) continue;
    final local = paidAt.toLocal().subtract(Duration(hours: cutoffHour));
    final day = DateTime(local.year, local.month, local.day);
    final net = _netAmount(row['amount'], row['change_amount']);
    final agg = byDay.putIfAbsent(day, _DayAgg.new);
    agg.total += net;
    agg.orders.add(oid);
    orders.add(oid);
    grossTotal += net;
  }

  final days = byDay.entries
      .map((e) => DailySalesEntry(
            date: e.key,
            total: e.value.total,
            orderCount: e.value.orders.length,
          ))
      .toList()
    ..sort((a, b) => a.date.compareTo(b.date));

  // ── Tax breakdown for the range, by tax name ──
  final taxes = aggregateTaxLines(taxRows);

  return DailySalesReport(
    days: days,
    grossTotal: grossTotal,
    taxes: taxes,
    orderCount: orders.length,
  );
}

double _netAmount(dynamic amount, dynamic changeAmount) =>
    _toDouble(amount) - _toDouble(changeAmount);

double _toDouble(dynamic value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? 0;
}

class _DayAgg {
  double total = 0;
  final orders = <String>{};
}
