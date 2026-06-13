import '../../domain/dashboard/dashboard_models.dart';

/// Pure aggregation for the sales-trend report. Given the raw paid `orders`
/// (id + closed_at) and their `payments` (amount, change, order_id) over
/// [rangeStart, rangeEnd), produces:
///  - contiguous time buckets (weeks or months), filling gaps with zero so the
///    trend chart has no holes; gross per bucket = payments net of change;
///  - a weekday×hour heatmap of the same sales.
///
/// Kept separate from the Supabase query so the bucketing/money math is
/// unit-testable. All times are converted to local before bucketing, matching
/// the other reports.
SalesTrendReport aggregateSalesTrend({
  required List<Map<String, dynamic>> orderRows,
  required List<Map<String, dynamic>> payRows,
  required DateTime rangeStart, // inclusive
  required DateTime rangeEnd, // exclusive
  required TrendGranularity granularity,
}) {
  DateTime dayOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  DateTime bucketStartFor(DateTime d) {
    if (granularity == TrendGranularity.month) return DateTime(d.year, d.month, 1);
    final day = dayOnly(d);
    return day.subtract(Duration(days: day.weekday - 1)); // back to Monday
  }

  DateTime nextBucket(DateTime b) => granularity == TrendGranularity.month
      ? DateTime(b.year, b.month + 1, 1)
      : b.add(const Duration(days: 7));

  // order id → local time, plus per-bucket order counts.
  final orderTime = <String, DateTime>{};
  final counts = <DateTime, int>{};
  for (final row in orderRows) {
    final id = row['id']?.toString();
    final ts = DateTime.tryParse(row['closed_at']?.toString() ?? '');
    if (id == null || id.isEmpty || ts == null) continue;
    final local = ts.toLocal();
    orderTime[id] = local;
    final b = bucketStartFor(local);
    counts[b] = (counts[b] ?? 0) + 1;
  }

  // payments → bucket totals + heatmap (keyed by weekday*100 + hour).
  final totals = <DateTime, double>{};
  final heat = <int, double>{};
  for (final row in payRows) {
    final oid = row['order_id']?.toString();
    if (oid == null) continue;
    final t = orderTime[oid];
    if (t == null) continue; // payment for an order outside this paid set
    final net = _toDouble(row['amount']) - _toDouble(row['change_amount']);
    final b = bucketStartFor(t);
    totals[b] = (totals[b] ?? 0) + net;
    final hk = t.weekday * 100 + t.hour;
    heat[hk] = (heat[hk] ?? 0) + net;
  }

  // Contiguous buckets across the range so the chart shows zero, not gaps.
  final buckets = <TrendBucket>[];
  if (rangeEnd.isAfter(rangeStart)) {
    final lastDay = dayOnly(rangeEnd).subtract(const Duration(days: 1));
    final stop = nextBucket(bucketStartFor(lastDay));
    var b = bucketStartFor(rangeStart);
    while (b.isBefore(stop)) {
      buckets.add(TrendBucket(
        start: b,
        total: totals[b] ?? 0,
        orderCount: counts[b] ?? 0,
      ));
      b = nextBucket(b);
    }
  }

  final heatCells = heat.entries
      .map((e) => HeatCell(weekday: e.key ~/ 100, hour: e.key % 100, total: e.value))
      .toList();

  return SalesTrendReport(
    buckets: buckets,
    heat: heatCells,
    granularity: granularity,
  );
}

double _toDouble(dynamic value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? 0;
}
