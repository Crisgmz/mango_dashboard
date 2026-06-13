import 'package:flutter_test/flutter_test.dart';
import 'package:mango_dashboard/data/export/export_filename.dart';

void main() {
  group('sanitizeExportFilename', () {
    test('removes "/" from custom-range labels (the ENOENT crash)', () {
      // "Ventas por día · 1/5 - 31/5" → filename seed below.
      final out = sanitizeExportFilename('ventas_por_dia_1/5_-_31/5');
      expect(out.contains('/'), isFalse);
      expect(out, 'ventas_por_dia_1-5_31-5');
    });

    test('handles a full dd/MM/yyyy range', () {
      final out = sanitizeExportFilename('ventas_por_dia_01/05/2026_-_31/05/2026');
      expect(out.contains('/'), isFalse);
      expect(out, 'ventas_por_dia_01-05-2026_31-05-2026');
    });

    test('leaves a clean name unchanged', () {
      expect(sanitizeExportFilename('ventas_por_dia_Ayer'), 'ventas_por_dia_Ayer');
    });

    test('strips every path-illegal character', () {
      final out = sanitizeExportFilename(r'a\b:c*d?e"f<g>h|i');
      for (final ch in [r'\', '/', ':', '*', '?', '"', '<', '>', '|']) {
        expect(out.contains(ch), isFalse, reason: 'still contains $ch');
      }
    });

    test('collapses whitespace and separator runs', () {
      expect(sanitizeExportFilename('a   b'), 'a_b');
      expect(sanitizeExportFilename('a___b'), 'a_b');
    });

    test('never returns empty', () {
      expect(sanitizeExportFilename('///'), 'reporte');
      expect(sanitizeExportFilename('   '), 'reporte');
      expect(sanitizeExportFilename(''), 'reporte');
    });
  });
}
