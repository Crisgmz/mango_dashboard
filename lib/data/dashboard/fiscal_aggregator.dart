import '../../domain/dashboard/dashboard_models.dart';
import 'tax_lines_aggregator.dart';

/// Pure aggregation for the fiscal report.
///  - [fiscalRows] (`fiscal_documents`): NCF by type and the consolidated
///    subtotal/itbis/total; cancelled documents are counted apart (anulados).
///  - [taxRows] (`order_item_tax_lines`): the real tax breakdown (ITBIS,
///    propina, …) by name.
FiscalReport aggregateFiscal({
  required List<Map<String, dynamic>> fiscalRows,
  required List<Map<String, dynamic>> taxRows,
}) {
  final byType = <String, _TypeAgg>{};
  var subtotal = 0.0, itbis = 0.0, total = 0.0;
  var documentCount = 0, cancelledCount = 0;

  for (final row in fiscalRows) {
    final status = row['status']?.toString().trim().toLowerCase();
    if (status == 'cancelled') {
      cancelledCount++;
      continue; // anulado — out of the active totals
    }

    final type = _nonEmpty(row['ncf_type']) ?? 'OTRO';
    final number = _nonEmpty(row['ncf_number']);
    final sub = _toDouble(row['subtotal']);
    final tax = _toDouble(row['itbis_amount']);
    final tot = _toDouble(row['total']);

    final agg = byType.putIfAbsent(type, _TypeAgg.new);
    agg.count++;
    agg.subtotal += sub;
    agg.itbis += tax;
    agg.total += tot;
    if (number != null) {
      agg.firstNumber ??= number;
      agg.lastNumber = number;
    }

    subtotal += sub;
    itbis += tax;
    total += tot;
    documentCount++;
  }

  final types = byType.entries
      .map((e) => FiscalTypeSummary(
            type: e.key,
            count: e.value.count,
            subtotal: e.value.subtotal,
            itbis: e.value.itbis,
            total: e.value.total,
            firstNumber: e.value.firstNumber,
            lastNumber: e.value.lastNumber,
          ))
      .toList()
    ..sort((a, b) => b.total.compareTo(a.total));

  return FiscalReport(
    byType: types,
    taxes: aggregateTaxLines(taxRows),
    subtotal: subtotal,
    itbis: itbis,
    total: total,
    documentCount: documentCount,
    cancelledCount: cancelledCount,
  );
}

class _TypeAgg {
  int count = 0;
  double subtotal = 0;
  double itbis = 0;
  double total = 0;
  String? firstNumber;
  String? lastNumber;
}

String? _nonEmpty(dynamic v) {
  final s = v?.toString().trim();
  return (s == null || s.isEmpty) ? null : s;
}

double _toDouble(dynamic value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? 0;
}
