import '../../domain/dashboard/dashboard_models.dart';

/// Pure aggregation for the operations report. Given paid `orders` embedding
/// their `table_sessions` (zone, origin, table, opened/closed, people) and the
/// `payments` for those orders, computes:
///  - gross sales by zone, by origin and by table (payments net of change);
///  - service metrics: distinct sessions, average table turnover (occupancy
///    time), total covers and ticket per person.
///
/// Revenue is attributed payment → order → session, and session-level facts
/// (turnover, covers) are counted once per distinct session so multiple orders
/// on one table don't double-count. Kept query-free so it is unit-testable.
OperationsReport aggregateOperations({
  required List<Map<String, dynamic>> orderRows,
  required List<Map<String, dynamic>> payRows,
}) {
  const noZone = 'Sin zona';
  const noTable = 'Sin mesa';
  const noOrigin = 'desconocido';

  // order id → its session's labels (for attributing payments).
  final orderZone = <String, String>{};
  final orderOrigin = <String, String>{};
  final orderTable = <String, String>{};
  // order-count per label.
  final zoneOrders = <String, int>{};
  final originOrders = <String, int>{};
  final tableOrders = <String, int>{};
  // distinct-session facts.
  final seenSessions = <String>{};
  final sessionPeople = <String, int>{};
  final sessionOpened = <String, DateTime>{};
  final sessionClosed = <String, DateTime>{};

  for (final row in orderRows) {
    final oid = row['id']?.toString();
    if (oid == null || oid.isEmpty) continue;

    final s = row['table_sessions'];
    final session = s is Map<String, dynamic> ? s : null;
    final table = session?['dining_tables'] is Map<String, dynamic>
        ? session!['dining_tables'] as Map<String, dynamic>
        : null;
    final zones = table?['zones'] is Map<String, dynamic>
        ? table!['zones'] as Map<String, dynamic>
        : null;

    final zone = _nonEmpty(zones?['name']) ?? noZone;
    final tableName = _nonEmpty(table?['name']) ?? noTable;
    final origin = _nonEmpty(session?['origin']) ?? noOrigin;

    orderZone[oid] = zone;
    orderOrigin[oid] = origin;
    orderTable[oid] = tableName;
    zoneOrders[zone] = (zoneOrders[zone] ?? 0) + 1;
    originOrders[origin] = (originOrders[origin] ?? 0) + 1;
    tableOrders[tableName] = (tableOrders[tableName] ?? 0) + 1;

    final sid = _nonEmpty(session?['id']);
    if (sid != null && seenSessions.add(sid)) {
      final people = _toInt(session?['people_count']);
      if (people > 0) sessionPeople[sid] = people;
      final opened = DateTime.tryParse(session?['opened_at']?.toString() ?? '');
      final closed = DateTime.tryParse(session?['closed_at']?.toString() ?? '');
      if (opened != null) sessionOpened[sid] = opened;
      if (closed != null) sessionClosed[sid] = closed;
    }
  }

  // Attribute each payment (net of change) to its order's labels.
  final zoneTotals = <String, double>{};
  final originTotals = <String, double>{};
  final tableTotals = <String, double>{};
  var totalSales = 0.0;
  for (final row in payRows) {
    final oid = row['order_id']?.toString();
    if (oid == null || !orderZone.containsKey(oid)) continue;
    final net = _toDouble(row['amount']) - _toDouble(row['change_amount']);
    totalSales += net;
    final z = orderZone[oid]!;
    final o = orderOrigin[oid]!;
    final t = orderTable[oid]!;
    zoneTotals[z] = (zoneTotals[z] ?? 0) + net;
    originTotals[o] = (originTotals[o] ?? 0) + net;
    tableTotals[t] = (tableTotals[t] ?? 0) + net;
  }

  List<NamedSales> ranked(Map<String, double> totals, Map<String, int> counts) =>
      totals.entries
          .map((e) => NamedSales(name: e.key, total: e.value, orderCount: counts[e.key] ?? 0))
          .toList()
        ..sort((a, b) => b.total.compareTo(a.total));

  // Average turnover over sessions with a valid, sane open→close span.
  var durSum = 0.0;
  var durCount = 0;
  for (final sid in seenSessions) {
    final op = sessionOpened[sid];
    final cl = sessionClosed[sid];
    if (op == null || cl == null) continue;
    final mins = cl.difference(op).inMinutes;
    if (mins > 0 && mins <= 24 * 60) {
      durSum += mins;
      durCount++;
    }
  }

  return OperationsReport(
    zones: ranked(zoneTotals, zoneOrders),
    origins: ranked(originTotals, originOrders),
    tables: ranked(tableTotals, tableOrders),
    totalSales: totalSales,
    orderCount: orderZone.length,
    sessionCount: seenSessions.length,
    avgTurnoverMinutes: durCount > 0 ? durSum / durCount : 0,
    totalCovers: sessionPeople.values.fold<int>(0, (a, b) => a + b),
  );
}

String? _nonEmpty(dynamic v) {
  final s = v?.toString().trim();
  return (s == null || s.isEmpty) ? null : s;
}

int _toInt(dynamic v) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse(v?.toString() ?? '') ?? 0;
}

double _toDouble(dynamic value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? 0;
}
