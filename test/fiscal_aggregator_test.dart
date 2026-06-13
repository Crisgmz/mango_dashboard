import 'package:flutter_test/flutter_test.dart';
import 'package:mango_dashboard/data/dashboard/fiscal_aggregator.dart';

void main() {
  final report = aggregateFiscal(
    fiscalRows: [
      {'ncf_type': 'B02', 'ncf_number': 'B0200000001', 'subtotal': 1000, 'itbis_amount': 180, 'total': 1180, 'status': 'active'},
      {'ncf_type': 'B02', 'ncf_number': 'B0200000002', 'subtotal': 2000, 'itbis_amount': 360, 'total': 2360, 'status': 'active'},
      {'ncf_type': 'E31', 'ncf_number': 'E310000000001', 'subtotal': 5000, 'itbis_amount': 900, 'total': 5900, 'status': 'active'},
      {'ncf_type': 'E31', 'ncf_number': 'E310000000002', 'subtotal': 1000, 'itbis_amount': 180, 'total': 1180, 'status': 'active'},
      {'ncf_type': 'E32', 'ncf_number': 'E320000000001', 'subtotal': '500', 'itbis_amount': '90', 'total': '590', 'status': 'active'},
      // Cancelled — excluded from totals, counted apart.
      {'ncf_type': 'B02', 'ncf_number': 'B0200000003', 'subtotal': 999, 'itbis_amount': 180, 'total': 1179, 'status': 'cancelled'},
    ],
    taxRows: [
      {'tax_name': 'ITBIS', 'tax_rate': 0.18, 'amount': 900},
      {'tax_name': 'ITBIS', 'tax_rate': 0.18, 'amount': '810'}, // string parse
      {'tax_name': 'Propina', 'tax_rate': 0, 'amount': 300}, // rate 0 → null
      {'tax_name': '  ', 'tax_rate': 0.18, 'amount': 5}, // blank → ignored
    ],
  );

  test('consolidated totals exclude cancelled documents', () {
    expect(report.subtotal, closeTo(9500, 1e-9)); // 1000+2000+5000+1000+500
    expect(report.itbis, closeTo(1710, 1e-9)); // 180+360+900+180+90
    expect(report.total, closeTo(11210, 1e-9));
    expect(report.documentCount, 5);
    expect(report.cancelledCount, 1);
  });

  test('NCF by type sorted by total desc, with number ranges', () {
    expect(report.byType.map((t) => t.type).toList(), ['E31', 'B02', 'E32']);
    final e31 = report.byType.firstWhere((t) => t.type == 'E31');
    expect(e31.count, 2);
    expect(e31.itbis, closeTo(1080, 1e-9)); // 900 + 180
    expect(e31.firstNumber, 'E310000000001');
    expect(e31.lastNumber, 'E310000000002');
    final b02 = report.byType.firstWhere((t) => t.type == 'B02');
    expect(b02.count, 2); // cancelled B02 not counted
  });

  test('real taxes breakdown by name, sorted desc, with average rate', () {
    expect(report.taxes.map((t) => t.name).toList(), ['ITBIS', 'Propina']);
    expect(report.taxes[0].amount, closeTo(1710, 1e-9)); // 900 + 810
    expect(report.taxes[0].rate, closeTo(0.18, 1e-9));
    expect(report.taxes[1].amount, closeTo(300, 1e-9));
    expect(report.taxes[1].rate, isNull); // only rate-0 lines
  });

  test('no documents → empty zeroed report', () {
    final empty = aggregateFiscal(fiscalRows: const [], taxRows: const []);
    expect(empty.documentCount, 0);
    expect(empty.itbis, 0);
    expect(empty.byType, isEmpty);
    expect(empty.taxes, isEmpty);
  });
}
