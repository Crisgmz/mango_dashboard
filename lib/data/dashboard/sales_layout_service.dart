import 'package:shared_preferences/shared_preferences.dart';

/// Identifies a section of the SalesView that the user can reorder.
enum SalesCard {
  kpis,
  monthProjection,
  productProjection,
  salesByMethod,
  hourlyChart,
  salesByCategory,
  topProducts,
  waiterPerformance,
  cashierPerformance,
  audit,
}

extension SalesCardLabel on SalesCard {
  /// Human-readable label shown in the customization sheet.
  String get label {
    switch (this) {
      case SalesCard.kpis:
        return 'Resumen (Ventas / Tickets / Ticket Promedio)';
      case SalesCard.monthProjection:
        return 'Proyección de fin de mes';
      case SalesCard.productProjection:
        return 'Proyección por producto';
      case SalesCard.salesByMethod:
        return 'Ventas por método de pago';
      case SalesCard.hourlyChart:
        return 'Ventas por hora';
      case SalesCard.salesByCategory:
        return 'Ventas por categoría';
      case SalesCard.topProducts:
        return 'Rendimiento por producto';
      case SalesCard.waiterPerformance:
        return 'Rendimiento por mesero';
      case SalesCard.cashierPerformance:
        return 'Rendimiento por cajero';
      case SalesCard.audit:
        return 'Auditoría de pérdidas';
    }
  }
}

/// Default order shown to users that have never customized the layout.
const List<SalesCard> kDefaultSalesLayout = [
  SalesCard.kpis,
  SalesCard.monthProjection,
  SalesCard.productProjection,
  SalesCard.salesByMethod,
  SalesCard.hourlyChart,
  SalesCard.salesByCategory,
  SalesCard.waiterPerformance,
  SalesCard.cashierPerformance,
  SalesCard.topProducts,
  SalesCard.audit,
];

/// Persists the user's preferred ordering of SalesView cards.
class SalesLayoutService {
  static const _prefsKey = 'sales_layout_order_v1';

  /// Loads the saved order, falling back to [kDefaultSalesLayout] when absent
  /// or invalid. Newly-added cards (not yet in the persisted list) are
  /// appended in their default-order position so the user keeps seeing them.
  Future<List<SalesCard>> loadOrder() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_prefsKey);
    if (raw == null || raw.isEmpty) return List.of(kDefaultSalesLayout);

    final parsed = <SalesCard>[];
    for (final name in raw) {
      final card = _byName(name);
      if (card != null && !parsed.contains(card)) parsed.add(card);
    }
    // Append any cards that weren't in the saved list (e.g. new feature added).
    for (final card in kDefaultSalesLayout) {
      if (!parsed.contains(card)) parsed.add(card);
    }
    return parsed;
  }

  Future<void> saveOrder(List<SalesCard> order) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_prefsKey, order.map((c) => c.name).toList());
  }

  Future<void> resetToDefault() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsKey);
  }

  static SalesCard? _byName(String name) {
    for (final card in SalesCard.values) {
      if (card.name == name) return card;
    }
    return null;
  }
}
