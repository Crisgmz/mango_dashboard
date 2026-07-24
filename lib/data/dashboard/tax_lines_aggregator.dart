import '../../domain/dashboard/dashboard_models.dart';

/// Aggregates raw `order_item_tax_lines` rows (tax_name, tax_rate, amount) into
/// per-named-tax totals, sorted by amount desc. The representative rate is the
/// average of the recorded positive rates (null when none). Shared by the daily
/// sales and fiscal reports so the tax math is defined once.
List<TaxLineTotal> aggregateTaxLines(List<Map<String, dynamic>> taxRows) {
  final agg = <String, _TaxAgg>{};
  for (final row in taxRows) {
    final name = row['tax_name']?.toString().trim();
    if (name == null || name.isEmpty) continue;
    final a = agg.putIfAbsent(name, _TaxAgg.new);
    a.amount += _toDouble(row['amount']);
    final rate = _toDouble(row['tax_rate']);
    if (rate > 0) {
      a.rateSum += rate;
      a.rateCount += 1;
    }
  }
  return agg.entries
      .map((e) => TaxLineTotal(
            name: e.key,
            amount: e.value.amount,
            rate: e.value.rateCount > 0 ? e.value.rateSum / e.value.rateCount : null,
          ))
      .toList()
    ..sort((a, b) => b.amount.compareTo(a.amount));
}

/// Fallback cuando el rango no tiene `order_item_tax_lines` (negocios/órdenes
/// anteriores al trigger que las puebla): deriva filas equivalentes desde
/// `order_items` (tax, tax_rate) cruzado con la config de `taxes` (nombre por
/// tasa) — espejo del reporte de impuestos del POS. Suma lo REALMENTE cobrado
/// por línea (precios inclusivos y exclusivos por igual); nunca base × tasa.
/// Si la tasa del ítem es el combinado de las tasas activas configuradas
/// (p. ej. 28 = 18 ITBIS + 10 Ley, caso legacy), se parte proporcionalmente.
/// Devuelve filas con la misma forma que `order_item_tax_lines`
/// (tax_name, tax_rate, amount) para alimentar [aggregateTaxLines].
List<Map<String, dynamic>> deriveTaxRowsFromItems({
  required List<Map<String, dynamic>> itemRows,
  required List<Map<String, dynamic>> taxConfigs,
}) {
  final nameByRate = <String, String>{};
  final activeRates = <double>[];
  for (final t in taxConfigs) {
    final rate = _toDouble(t['rate']);
    if (rate <= 0) continue;
    final name = t['name']?.toString().trim() ?? '';
    if (name.isNotEmpty) nameByRate[rate.toStringAsFixed(4)] = name;
    if (t['is_active'] == true) activeRates.add(rate);
  }
  final combinedRate = activeRates.fold<double>(0, (s, r) => s + r);

  final rows = <Map<String, dynamic>>[];
  void addRow(double rate, double amount) {
    if (amount == 0) return;
    final key = rate.toStringAsFixed(4);
    final fallbackName =
        'Impuesto ${rate == rate.roundToDouble() ? rate.toStringAsFixed(0) : rate.toStringAsFixed(2)}%';
    rows.add(<String, dynamic>{
      'tax_name': nameByRate[key] ?? fallbackName,
      'tax_rate': rate,
      'amount': amount,
    });
  }

  for (final item in itemRows) {
    if (item['status']?.toString() == 'void') continue;
    final tax = _toDouble(item['tax']);
    if (tax == 0) continue;
    final rate = _toDouble(item['tax_rate']);
    // Tasa combinada legacy (la suma de las configuradas, sin match directo
    // con ninguna tasa individual): partir proporcional entre las activas.
    final isCombined = activeRates.length > 1 &&
        !nameByRate.containsKey(rate.toStringAsFixed(4)) &&
        combinedRate > 0 &&
        (rate - combinedRate).abs() < 0.01;
    if (isCombined) {
      for (final r in activeRates) {
        addRow(r, tax * (r / combinedRate));
      }
    } else {
      addRow(rate, tax);
    }
  }
  return rows;
}

class _TaxAgg {
  double amount = 0;
  double rateSum = 0;
  int rateCount = 0;
}

double _toDouble(dynamic value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? 0;
}
