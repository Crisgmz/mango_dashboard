import '../../domain/dashboard/dashboard_models.dart';

/// Prefix for waiter keys that could only be resolved to an auth user.
const waiterUserKeyPrefix = 'user:';

/// Pure attribution of comandas to meseros, with the same rule the POS report
/// `fn_sales_by_waiter` uses:
/// `coalesce(order_items.created_by_employee_id, table_sessions.opened_by_employee_id)`
/// — the employee identified by the PIN typed to ring items into the account.
///
/// That priority is the whole point: whoever logged the device into the system
/// (`table_sessions.opened_by` / `waiter_user_id`) is often a cashier or the
/// owner, not the mesero who worked the table. The auth user is only a last
/// resort, for businesses that don't use PINs, and even then it's mapped back
/// to an employee through `employees.user_id` so one person never shows up as
/// two different meseros.
///
/// Returns a map keyed by `orderId` and also by `orderId::checkId` (split
/// bills), each holding that scope's meseros ordered by how much they entered.
/// Kept query-free so it is unit-testable.
Map<String, List<TicketWaiter>> aggregateWaiterAttribution({
  required List<Map<String, dynamic>> orderRows,
  required List<Map<String, dynamic>> itemRows,
  required List<Map<String, dynamic>> employeeRows,
  Map<String, String> userNames = const {},
}) {
  const fallbackName = 'Mesero';

  final employeeNames = <String, String>{};
  final employeeByUser = <String, String>{};
  for (final row in employeeRows) {
    final id = _text(row['id']);
    if (id == null) continue;
    final name = [row['first_name'], row['last_name']]
        .map((v) => v?.toString().trim() ?? '')
        .where((v) => v.isNotEmpty)
        .join(' ');
    if (name.isNotEmpty) employeeNames[id] = name;
    final userId = _text(row['user_id']);
    if (userId != null) employeeByUser[userId] = id;
  }

  // Session-level attribution — the fallback for lines typed with no PIN.
  final sessionEmployee = <String, String>{};
  final sessionUser = <String, String>{};
  final orderIds = <String>[];
  for (final row in orderRows) {
    final orderId = _text(row['id']);
    if (orderId == null) continue;
    orderIds.add(orderId);
    final session = row['table_sessions'];
    if (session is! Map<String, dynamic>) continue;
    final employeeId = _text(session['opened_by_employee_id']);
    if (employeeId != null) sessionEmployee[orderId] = employeeId;
    final userId =
        _text(session['waiter_user_id']) ?? _text(session['opened_by']);
    if (userId != null) sessionUser[orderId] = userId;
  }

  String? waiterKeyFor(String orderId, String? lineEmployeeId) {
    final employeeId = lineEmployeeId ?? sessionEmployee[orderId];
    if (employeeId != null) return employeeId;
    final userId = sessionUser[orderId];
    if (userId == null) return null;
    return employeeByUser[userId] ?? '$waiterUserKeyPrefix$userId';
  }

  // scope key -> waiter key -> amount that mesero entered in that scope.
  final amounts = <String, Map<String, double>>{};
  void addAmount(String scope, String waiterKey, double amount) {
    final byWaiter = amounts.putIfAbsent(scope, () => <String, double>{});
    byWaiter[waiterKey] = (byWaiter[waiterKey] ?? 0) + amount;
  }

  for (final row in itemRows) {
    if (row['status']?.toString() == 'void') continue;
    final orderId = _text(row['order_id']);
    if (orderId == null) continue;
    final key = waiterKeyFor(orderId, _text(row['created_by_employee_id']));
    if (key == null) continue;
    // Line amount is subtotal+tax−discounts, never order_items.total.
    final net = _toDouble(row['subtotal']) +
        _toDouble(row['tax']) -
        _toDouble(row['discounts']);
    addAmount(orderId, key, net);
    final checkId = _text(row['check_id']);
    if (checkId != null) addAmount('$orderId::$checkId', key, net);
  }

  // Orders whose lines carried no attribution still get their session's
  // mesero, so they don't fall out of a filtered list.
  for (final orderId in orderIds) {
    if (amounts.containsKey(orderId)) continue;
    final key = waiterKeyFor(orderId, null);
    if (key != null) addAmount(orderId, key, 0);
  }

  final result = <String, List<TicketWaiter>>{};
  amounts.forEach((scope, byWaiter) {
    final entries = byWaiter.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    result[scope] = entries.map((entry) {
      final key = entry.key;
      final name = key.startsWith(waiterUserKeyPrefix)
          ? userNames[key.substring(waiterUserKeyPrefix.length)] ?? fallbackName
          : employeeNames[key] ?? fallbackName;
      return TicketWaiter(id: key, name: name);
    }).toList(growable: false);
  });
  return result;
}

/// Auth user ids that back the sessions of [orderRows] and don't belong to any
/// employee in [employeeRows] — the ones whose display name has to be resolved
/// elsewhere before attributing.
Set<String> waiterUserIdsToResolve({
  required List<Map<String, dynamic>> orderRows,
  required List<Map<String, dynamic>> employeeRows,
}) {
  final known = <String>{};
  for (final row in employeeRows) {
    final userId = _text(row['user_id']);
    if (userId != null) known.add(userId);
  }
  final pending = <String>{};
  for (final row in orderRows) {
    final session = row['table_sessions'];
    if (session is! Map<String, dynamic>) continue;
    final userId =
        _text(session['waiter_user_id']) ?? _text(session['opened_by']);
    if (userId != null && !known.contains(userId)) pending.add(userId);
  }
  return pending;
}

/// Trimmed value, or null when absent/blank — Supabase hands back both `null`
/// and `''` for unset columns depending on the join.
String? _text(dynamic value) {
  final text = value?.toString().trim() ?? '';
  return text.isEmpty ? null : text;
}

double _toDouble(dynamic value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? 0;
}
