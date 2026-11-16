import '../../domain/dashboard/dashboard_models.dart';

/// Pure aggregation for the sales-trend report. Given the sale `payments`
/// (amount, change, order_id, created_at) over [rangeStart, rangeEnd) — a sale
/// is the payment, placed when it was collected (sale_scope.dart) — produces:
///  - contiguous time buckets (weeks or months), filling gaps with zero so the
///    trend chart has no holes; gross per bucket = payments net of change;
///  - a weekday×hour heatmap of the same sales.
///
/// Kept separate from the Supabase query so the bucketing/money math is
/// unit-testable. All times are converted to local before bucketing, matching
/// the other reports.
SalesTrendReport aggregateSalesTrend({
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

  // payments → bucket totals, distinct orders per bucket and the heatmap
  // (keyed by weekday*100 + hour), all at the moment of the payment.
  final totals = <DateTime, double>{};
  final orders = <DateTime, Set<String>>{};
  final heat = <int, double>{};
  for (final row in payRows) {
    final oid = row['order_id']?.toString();
    final ts = DateTime.tryParse(row['created_at']?.toString() ?? '');
    if (oid == null || oid.isEmpty || ts == null) continue;
    final t = ts.toLocal();
    final net = _toDouble(row['amount']) - _toDouble(row['change_amount']);
    final b = bucketStartFor(t);
    totals[b] = (totals[b] ?? 0) + net;
    orders.putIfAbsent(b, () => <String>{}).add(oid);
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
        orderCount: orders[b]?.length ?? 0,
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
