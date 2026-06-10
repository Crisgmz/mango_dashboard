import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../core/formatters/mango_formatters.dart';
import '../../domain/dashboard/dashboard_models.dart';

/// Builds the PDF document for a cash session "Reporte Z" — receipt-style
/// layout sized for an 80mm thermal-printer page (also looks fine on letter
/// size when printed). Designed to mirror the on-screen `_ReporteZReceipt`.
class ReporteZPdfBuilder {
  static const _pageWidth = 80 * PdfPageFormat.mm; // ~80mm wide receipt
  static const _pageMargin = 6.0;

  static Future<pw.Document> build({
    required RegisterClosing closing,
    required String businessName,
    required List<NcfTypeSummary> ncfs,
    DateTime? generatedAt,
  }) async {
    final doc = pw.Document();
    final now = generatedAt ?? DateTime.now();

    final openedAt = closing.openedAt;
    final duration = openedAt == null ? null : closing.closedAt.difference(openedAt);
    final cashExpected = closing.openingAmount +
        closing.cashSales +
        closing.totalDeposits -
        closing.totalWithdrawals -
        closing.totalExpenses;
    final cashDifference = closing.closingAmount - cashExpected;
    final ncfTotalCount = ncfs.fold<int>(0, (s, n) => s + n.count);
    final ncfTotalAmount = ncfs.fold<double>(0, (s, n) => s + n.total);

    // Use a tall rolling format that grows with content — perfect for receipts.
    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat(
          _pageWidth,
          double.infinity,
          marginAll: _pageMargin,
        ),
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            _header(businessName),
            _dashedDivider(),
            pw.SizedBox(height: 6),
            _row('Caja', closing.registerName),
            _row('Cajero', closing.closedByName),
            if (closing.deviceName != null && closing.deviceName!.trim().isNotEmpty)
              _row('Dispositivo', closing.deviceName!),
            if (openedAt != null) _row('Apertura', MangoFormatters.dateTime(openedAt)),
            _row('Cierre', MangoFormatters.dateTime(closing.closedAt)),
            if (duration != null) _row('Duración', _formatDuration(duration)),
            pw.SizedBox(height: 8),
            _solidDivider(),
            _sectionTitle('VENTAS'),
            _row('Efectivo', MangoFormatters.currency(closing.cashSales)),
            _row('Tarjeta', MangoFormatters.currency(closing.cardSales)),
            _row('Transferencia', MangoFormatters.currency(closing.transferSales)),
            if (closing.otherSales > 0)
              _row('Otros', MangoFormatters.currency(closing.otherSales)),
            pw.SizedBox(height: 4),
            _row('TOTAL VENTAS', MangoFormatters.currency(closing.totalSales), bold: true),
            pw.SizedBox(height: 8),
            _solidDivider(),
            _sectionTitle('CAJA EN EFECTIVO'),
            _row('Apertura', MangoFormatters.currency(closing.openingAmount)),
            _row('+ Ventas efectivo', MangoFormatters.currency(closing.cashSales)),
            _row('+ Depósitos', MangoFormatters.currency(closing.totalDeposits)),
            _row('- Retiros', MangoFormatters.currency(closing.totalWithdrawals)),
            _row('- Gastos', MangoFormatters.currency(closing.totalExpenses)),
            pw.SizedBox(height: 4),
            _row('Esperado', MangoFormatters.currency(cashExpected), bold: true),
            _row('Contado al cierre', MangoFormatters.currency(closing.closingAmount), bold: true),
            pw.SizedBox(height: 4),
            _row(
              cashDifference == 0
                  ? 'Dif. efectivo'
                  : (cashDifference > 0 ? 'Sobrante efectivo' : 'Faltante efectivo'),
              MangoFormatters.currency(cashDifference.abs()),
              bold: true,
            ),
            pw.SizedBox(height: 8),
            _solidDivider(),
            _sectionTitle('RESULTADO DEL CIERRE'),
            _row('Total esperado', MangoFormatters.currency(closing.expectedTotal)),
            _row('Total reportado', MangoFormatters.currency(closing.reportedTotal)),
            pw.SizedBox(height: 4),
            _row(
              closing.netDifference == 0
                  ? 'Diferencia neta'
                  : (closing.netDifference > 0 ? 'Sobrante (neto)' : 'Faltante (neto)'),
              MangoFormatters.currency(closing.netDifference.abs()),
              bold: true,
              valueColor: closing.netDifference == 0
                  ? null
                  : (closing.netDifference > 0 ? PdfColors.green700 : PdfColors.red700),
            ),
            pw.SizedBox(height: 4),
            _row('Dif. efectivo', _signed(closing.cashDifference)),
            _row('Dif. tarjeta', _signed(closing.cardDifference)),
            _row('Dif. transferencia', _signed(closing.transferDifference)),
            if (!closing.hasReportedBreakdown)
              pw.Padding(
                padding: const pw.EdgeInsets.only(top: 3),
                child: pw.Text(
                  'Sin desglose reportado por método; la diferencia neta refleja solo el efectivo.',
                  style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
                ),
              ),
            pw.SizedBox(height: 8),
            _solidDivider(),
            _sectionTitle('COMPROBANTES FISCALES (NCF)'),
            if (ncfs.isEmpty)
              pw.Padding(
                padding: const pw.EdgeInsets.symmetric(vertical: 4),
                child: pw.Text(
                  'Sin NCFs emitidos en este turno.',
                  style: const pw.TextStyle(fontSize: 9),
                ),
              )
            else ...[
              for (final ncf in ncfs) ...[
                _row('${ncf.type} (${ncf.count})', MangoFormatters.currency(ncf.total)),
                if (ncf.firstNumber != null && ncf.lastNumber != null)
                  pw.Padding(
                    padding: const pw.EdgeInsets.only(left: 6, bottom: 3),
                    child: pw.Text(
                      ncf.firstNumber == ncf.lastNumber
                          ? ncf.firstNumber!
                          : '${ncf.firstNumber} → ${ncf.lastNumber}',
                      style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
                    ),
                  ),
              ],
              pw.SizedBox(height: 4),
              _row('Total NCFs', '$ncfTotalCount comprobantes', bold: true),
              _row('Total facturado', MangoFormatters.currency(ncfTotalAmount), bold: true),
            ],
            pw.SizedBox(height: 12),
            _dashedDivider(),
            pw.SizedBox(height: 18),
            _signatureLine('Firma cajero'),
            pw.SizedBox(height: 18),
            _signatureLine('Firma supervisor'),
            pw.SizedBox(height: 10),
            pw.Center(
              child: pw.Text(
                'Generado: ${MangoFormatters.dateTime(now)}',
                style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey600),
              ),
            ),
          ],
        ),
      ),
    );

    return doc;
  }

  static pw.Widget _header(String businessName) {
    return pw.Column(
      children: [
        pw.Text(
          businessName.toUpperCase(),
          style: pw.TextStyle(
            fontSize: 12,
            fontWeight: pw.FontWeight.bold,
            letterSpacing: 1.0,
          ),
          textAlign: pw.TextAlign.center,
        ),
        pw.SizedBox(height: 2),
        pw.Text(
          'REPORTE DE CIERRE DE TURNO',
          style: pw.TextStyle(
            fontSize: 9,
            fontWeight: pw.FontWeight.bold,
            color: PdfColors.grey700,
            letterSpacing: 1.2,
          ),
        ),
        pw.SizedBox(height: 6),
      ],
    );
  }

  static pw.Widget _row(String label, String value, {bool bold = false, PdfColor? valueColor}) {
    final style = pw.TextStyle(
      fontSize: bold ? 10 : 9,
      fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
    );
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 1.5),
      child: pw.Row(
        children: [
          pw.Expanded(child: pw.Text(label, style: style)),
          pw.Text(value, style: valueColor == null ? style : style.copyWith(color: valueColor)),
        ],
      ),
    );
  }

  /// Currency with an explicit sign (`+RD$ …` / `−RD$ …`) for difference rows.
  static String _signed(double v) {
    if (v == 0) return MangoFormatters.currency(0);
    final sign = v > 0 ? '+' : '−';
    return '$sign${MangoFormatters.currency(v.abs())}';
  }

  static pw.Widget _sectionTitle(String title) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 4),
      child: pw.Text(
        title,
        style: pw.TextStyle(
          fontSize: 9,
          fontWeight: pw.FontWeight.bold,
          letterSpacing: 1.0,
          color: PdfColors.orange800,
        ),
      ),
    );
  }

  static pw.Widget _solidDivider() {
    return pw.Container(
      height: 0.8,
      color: PdfColors.grey400,
      margin: const pw.EdgeInsets.symmetric(vertical: 2),
    );
  }

  static pw.Widget _dashedDivider() {
    return pw.Container(
      height: 0.8,
      decoration: const pw.BoxDecoration(
        border: pw.Border(
          top: pw.BorderSide(color: PdfColors.grey400, width: 0.5, style: pw.BorderStyle.dashed),
        ),
      ),
    );
  }

  static pw.Widget _signatureLine(String label) {
    return pw.Column(
      children: [
        pw.Container(
          width: double.infinity,
          height: 0.6,
          color: PdfColors.black,
          margin: const pw.EdgeInsets.symmetric(horizontal: 12),
        ),
        pw.SizedBox(height: 2),
        pw.Center(
          child: pw.Text(
            label,
            style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
          ),
        ),
      ],
    );
  }

  static String _formatDuration(Duration d) {
    final hours = d.inHours;
    final minutes = d.inMinutes.remainder(60);
    if (hours == 0) return '${minutes}m';
    return '${hours}h ${minutes}m';
  }
}
