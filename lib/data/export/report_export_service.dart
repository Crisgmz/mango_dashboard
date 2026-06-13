import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import 'export_filename.dart';

/// Helpers to export tabular report data as CSV or PDF and trigger the
/// platform share sheet. Used by the report screens (sales, products,
/// customers, modifiers, audit) so the user can hand the data over to
/// accounting or print it.
class ReportExportService {
  /// Builds CSV bytes from [headers] + [rows] and shares them as
  /// `<filename>.csv`.
  static Future<void> exportCsv({
    required String filename,
    required List<String> headers,
    required List<List<String>> rows,
    String? subject,
  }) async {
    final buffer = StringBuffer();
    buffer.writeln(headers.map(_escape).join(','));
    for (final row in rows) {
      buffer.writeln(row.map(_escape).join(','));
    }
    // BOM so Excel detects UTF-8 (avoids broken accents).
    final bytes = Uint8List.fromList(
        [0xEF, 0xBB, 0xBF, ...buffer.toString().codeUnits]);
    await _share(
      bytes: bytes,
      filename: '${sanitizeExportFilename(filename)}.csv',
      mimeType: 'text/csv',
      subject: subject,
    );
  }

  /// Builds a simple tabular PDF and shares it. The document is laid out on a
  /// background isolate ([compute]) — rendering a long table (e.g. a full month
  /// of daily sales) is CPU-bound and would otherwise freeze the UI thread.
  static Future<void> exportPdf({
    required String filename,
    required String title,
    String? subtitle,
    required List<String> headers,
    required List<List<String>> rows,
  }) async {
    final bytes = await compute(
      _renderPdf,
      (title: title, subtitle: subtitle, headers: headers, rows: rows),
    );
    await Printing.sharePdf(bytes: bytes, filename: '${sanitizeExportFilename(filename)}.pdf');
  }

  static String _escape(String value) {
    final needsQuotes =
        value.contains(',') || value.contains('"') || value.contains('\n');
    final escaped = value.replaceAll('"', '""');
    return needsQuotes ? '"$escaped"' : escaped;
  }

  static Future<void> _share({
    required Uint8List bytes,
    required String filename,
    required String mimeType,
    String? subject,
  }) async {
    if (kIsWeb) {
      await SharePlus.instance.share(ShareParams(
        files: [XFile.fromData(bytes, name: filename, mimeType: mimeType)],
        subject: subject,
        fileNameOverrides: [filename],
      ));
      return;
    }
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$filename');
    await file.writeAsBytes(bytes, flush: true);
    await SharePlus.instance.share(ShareParams(
      files: [XFile(file.path, mimeType: mimeType, name: filename)],
      subject: subject,
    ));
  }
}

/// Serializable input for [_renderPdf] (records cross isolate boundaries).
typedef _PdfJob = ({
  String title,
  String? subtitle,
  List<String> headers,
  List<List<String>> rows,
});

/// Builds the PDF bytes. Top-level so it can run on a background isolate via
/// [compute]; everything it touches (data + `pw` widgets) is created here, so
/// no Flutter/UI state crosses the isolate boundary.
Future<Uint8List> _renderPdf(_PdfJob job) {
  final doc = pw.Document();
  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(28),
      header: (ctx) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(job.title,
              style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
          if (job.subtitle != null && job.subtitle!.isNotEmpty) ...[
            pw.SizedBox(height: 2),
            pw.Text(job.subtitle!,
                style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
          ],
          pw.SizedBox(height: 10),
        ],
      ),
      footer: (ctx) => pw.Padding(
        padding: const pw.EdgeInsets.only(top: 8),
        child: pw.Text(
          'Página ${ctx.pageNumber} / ${ctx.pagesCount}',
          style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600),
        ),
      ),
      build: (ctx) => [
        pw.TableHelper.fromTextArray(
          headers: job.headers,
          data: job.rows,
          headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10),
          cellStyle: const pw.TextStyle(fontSize: 9),
          headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
          cellPadding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          cellAlignment: pw.Alignment.centerLeft,
        ),
      ],
    ),
  );
  return doc.save();
}

/// Drop-in AppBar action that opens a CSV/PDF export menu. The parent
/// passes async callbacks that build the rows and call
/// [ReportExportService.exportCsv] / [exportPdf].
class ExportMenuButton extends StatelessWidget {
  const ExportMenuButton({
    super.key,
    required this.onExportCsv,
    required this.onExportPdf,
    this.enabled = true,
  });

  final Future<void> Function() onExportCsv;
  final Future<void> Function() onExportPdf;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.ios_share_rounded),
      tooltip: 'Exportar',
      enabled: enabled,
      onSelected: (v) async {
        final navigator = Navigator.of(context, rootNavigator: true);
        final messenger = ScaffoldMessenger.of(context);
        // Feedback while the file is built (and a guard against double-taps).
        showDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (_) => const Center(child: CircularProgressIndicator()),
        );
        try {
          if (v == 'csv') {
            await onExportCsv();
          } else if (v == 'pdf') {
            await onExportPdf();
          }
        } catch (_) {
          messenger.showSnackBar(
            const SnackBar(content: Text('No se pudo generar el archivo para exportar.')),
          );
        } finally {
          navigator.pop(); // dismiss the progress dialog
        }
      },
      itemBuilder: (_) => const [
        PopupMenuItem(
          value: 'csv',
          child: Row(children: [
            Icon(Icons.table_chart_rounded, size: 18),
            SizedBox(width: 10),
            Text('Exportar CSV'),
          ]),
        ),
        PopupMenuItem(
          value: 'pdf',
          child: Row(children: [
            Icon(Icons.picture_as_pdf_rounded, size: 18),
            SizedBox(width: 10),
            Text('Exportar PDF'),
          ]),
        ),
      ],
    );
  }
}
