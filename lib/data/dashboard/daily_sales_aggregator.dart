import '../../domain/dashboard/dashboard_models.dart';
import 'tax_lines_aggregator.dart';

/// Pure aggregation for the "Ventas por día" report. Given the raw `orders`,
/// `payments` and `order_item_tax_lines` rows already fetched for the range,
/// computes per-day gross sales, the range-wide tax breakdown, and totals.
///
/// Kept separate from the Supabase query so the money math is unit-testable:
///  - gross per day = its paid orders' payments, net of change;
///  - `netTotal = grossTotal − Σ taxes` (see [DailySalesReport]);
///  - taxes aggregated by name, with the average rate when one is recorded.
DailySalesReport aggregateDailySales({
  required List<Map<String, dynamic>> orderRows,
  required List<Map<String, dynamic>> payRows,
  required List<Map<String, dynamic>> taxRows,
}) {
  // ── Map each paid order to its local day + per-day count ──
  final orderDay = <String, DateTime>{};
  final byDay = <DateTime, _DayAgg>{};
  var orderCount = 0;

  for (final row in orderRows) {
    final id = row['id']?.toString();
    final closedAt = DateTime.tryParse(row['closed_at']?.toString() ?? '');
    if (id == null || id.isEmpty || closedAt == null) continue;
    final local = closedAt.toLocal();
    final day = DateTime(local.year, local.month, local.day);
    orderDay[id] = day;
    byDay.putIfAbsent(day, _DayAgg.new).count += 1;
    orderCount += 1;
  }

  // ── Gross per day = those orders' payments (net of change) ──
  double grossTotal = 0;
  for (final row in payRows) {
    final oid = row['order_id']?.toString();
    if (oid == null) continue;
    final day = orderDay[oid];
    if (day == null) continue; // not a paid order closed in this range
    final net = _netAmount(row['amount'], row['change_amount']);
    byDay[day]!.total += net;
    grossTotal += net;
  }

  final days = byDay.entries
      .map((e) => DailySalesEntry(
            date: e.key,
            total: e.value.total,
            orderCount: e.value.count,
          ))
      .toList()
    ..sort((a, b) => a.date.compareTo(b.date));

  // ── Tax breakdown for the range, by tax name ──
  final taxes = aggregateTaxLines(taxRows);

  return DailySalesReport(
    days: days,
    grossTotal: grossTotal,
    taxes: taxes,
    orderCount: orderCount,
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
  int count = 0;
}
