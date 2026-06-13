import 'package:flutter_test/flutter_test.dart';
import 'package:mango_dashboard/data/dashboard/menu_engineering_aggregator.dart';

void main() {
  final report = aggregateMenuEngineering(
    menuNames: const ['Mofongo', 'Sancocho', 'Ensalada César', 'Flan', 'Jugo'],
    sold: const [
      (name: 'MOFONGO', units: 50, revenue: 5000), // case differs from menu
      (name: 'Sancocho', units: 40, revenue: 1000),
      (name: 'Flan', units: 5, revenue: 2500),
      (name: 'Jugo', units: 3, revenue: 150),
      (name: 'Especial del día', units: 10, revenue: 800), // sold, not in menu
    ],
  );

  test('counts active menu items (distinct)', () {
    expect(report.menuSize, 5);
  });

  test('dead items = active menu not sold, matched case-insensitively', () {
    // "MOFONGO" sold matches menu "Mofongo" → only "Ensalada César" is dead.
    expect(report.deadItems, ['Ensalada César']);
  });

  test('selling sorted by revenue desc', () {
    expect(report.selling.map((p) => p.revenue).toList(),
        [5000, 2500, 1000, 800, 150]);
  });

  test('totals', () {
    expect(report.totalRevenue, closeTo(9450, 1e-9));
  });

  test('no menu, no sales → empty report', () {
    final empty = aggregateMenuEngineering(menuNames: const [], sold: const []);
    expect(empty.menuSize, 0);
    expect(empty.deadItems, isEmpty);
    expect(empty.selling, isEmpty);
    expect(empty.totalRevenue, 0);
  });

  test('all sold → no dead items', () {
    final r = aggregateMenuEngineering(
      menuNames: const ['A', 'B'],
      sold: const [(name: 'A', units: 1, revenue: 10), (name: 'B', units: 2, revenue: 20)],
    );
    expect(r.deadItems, isEmpty);
  });
}
