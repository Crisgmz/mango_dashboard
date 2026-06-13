import '../../domain/dashboard/dashboard_models.dart';

/// Pure menu aggregation. Given the active menu item names and the period's
/// sold products (label + units + revenue, e.g. from `loadTopProductsForPeriod`),
/// it ranks the sold products by revenue and lists the active menu items that
/// did not sell at all (dead items).
///
/// Matching is by normalized name (trim + lowercase) since `order_items` stores
/// a product_name snapshot.
MenuEngineeringReport aggregateMenuEngineering({
  required List<String> menuNames,
  required List<({String name, double units, double revenue})> sold,
}) {
  String norm(String s) => s.trim().toLowerCase();

  // Merge sold products by normalized name (defensive against duplicates).
  final byKey = <String, ({String name, double units, double revenue})>{};
  for (final p in sold) {
    final key = norm(p.name);
    if (key.isEmpty) continue;
    final cur = byKey[key];
    byKey[key] = (
      name: cur?.name ?? p.name,
      units: (cur?.units ?? 0) + p.units,
      revenue: (cur?.revenue ?? 0) + p.revenue,
    );
  }

  final stats = byKey.values
      .where((p) => p.units > 0)
      .map((p) => MenuItemStat(name: p.name, units: p.units, revenue: p.revenue))
      .toList()
    ..sort((a, b) => b.revenue.compareTo(a.revenue));

  // Dead items: active menu names with no sales.
  final soldKeys = byKey.keys.toSet();
  final seenMenu = <String>{};
  final dead = <String>[];
  for (final name in menuNames) {
    final key = norm(name);
    if (key.isEmpty || !seenMenu.add(key)) continue;
    if (!soldKeys.contains(key)) dead.add(name.trim());
  }
  dead.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

  return MenuEngineeringReport(
    selling: stats,
    deadItems: dead,
    menuSize: seenMenu.length,
  );
}
