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

class _TaxAgg {
  double amount = 0;
  double rateSum = 0;
  int rateCount = 0;
}

double _toDouble(dynamic value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? 0;
}
