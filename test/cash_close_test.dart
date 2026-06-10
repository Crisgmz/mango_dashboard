import 'package:flutter_test/flutter_test.dart';
import 'package:mango_dashboard/data/cash_register/cash_close_notes.dart';
import 'package:mango_dashboard/domain/dashboard/dashboard_models.dart';

void main() {
  group('parseCashCloseNotes', () {
    test('parses blind close (plural labels) and ignores Dif. fields', () {
      const notes =
          'Cierre ciego | Efectivo: 24,310.00 | Tarjetas: 39,675.00 | '
          'Transferencias: 0.00 | Total reportado: 63,985.00 | '
          'Dif. efectivo: 2700 | Dif. tarjeta: -2550 | Dif. total: 63985';
      final r = parseCashCloseNotes(notes);
      expect(r.mode, 'blind');
      expect(r.cash, 24310);
      expect(r.card, 39675);
      expect(r.transfer, 0);
      expect(r.total, 63985);
    });

    test('parses detailed close (singular labels)', () {
      const notes =
          'Cierre detallado | Efectivo: 100 | Tarjeta: 200 | '
          'Transferencia: 50 | Total reportado: 350';
      final r = parseCashCloseNotes(notes);
      expect(r.mode, 'detailed');
      expect(r.cash, 100);
      expect(r.card, 200);
      expect(r.transfer, 50);
      expect(r.total, 350);
    });

    test('captures forced-close note', () {
      const notes =
          'Cierre ciego | Efectivo: 0 | Total reportado: 0 | '
          'Cierre forzado con 2 mesa(s) abiertas';
      final r = parseCashCloseNotes(notes);
      expect(r.forcedCloseNote, 'Cierre forzado con 2 mesa(s) abiertas');
    });

    test('empty/null notes yield no reported values', () {
      expect(parseCashCloseNotes(null).total, isNull);
      expect(parseCashCloseNotes('').cash, isNull);
    });
  });

  group('RegisterClosing reconciliation — PRD example (business 800e4643…)', () {
    // From the real Reporte Z (09/06/2026):
    //   Apertura 8,780 · Ventas efectivo 13,050 · Depósitos 500 · Retiros 720
    //   → expected_cash = 8,780 + 13,050 + 500 − 720 = 21,610
    //   Contado al cierre (end_amount) = 24,310 (reported cash)
    //   Ventas tarjeta (payments) = expected_card = 42,225
    //   Reported card (from notes) = 39,675
    final closing = RegisterClosing(
      id: 's1',
      registerName: 'Caja 1',
      closedAt: DateTime(2026, 6, 9),
      closedByName: 'Cajero',
      openingAmount: 8780,
      cashSales: 13050,
      totalDeposits: 500,
      totalWithdrawals: 720,
      totalExpenses: 0,
      closingAmount: 24310,
      difference: 2700,
      cardSales: 42225,
      transferSales: 0,
      // reported card from notes (the only non-structured input):
      reportedCard: 39675,
      reportedTransfer: 0,
    );

    test('expected per method derived without RPC', () {
      expect(closing.expectedCash, 21610);
      expect(closing.expectedCard, 42225);
      expect(closing.expectedTransfer, 0);
      expect(closing.expectedTotal, 63835);
    });

    test('reported per method resolves correctly', () {
      expect(closing.reportedCashResolved, 24310);
      expect(closing.reportedCardResolved, 39675);
      expect(closing.reportedTotal, 63985);
    });

    test('NET difference is +150, not the cash-only 2,700', () {
      expect(closing.netDifference, 150);
      expect(closing.difference, 2700); // cash-only drawer reconciliation
    });

    test('per-method differences reveal the +cash / −card pattern', () {
      expect(closing.cashDifference, 2700);
      expect(closing.cardDifference, -2550);
      expect(closing.transferDifference, 0);
    });

    test('net equals the sum of per-method differences', () {
      expect(
        closing.cashDifference + closing.cardDifference + closing.transferDifference,
        closing.netDifference,
      );
    });
  });

  group('RegisterClosing reconciliation — no reported breakdown', () {
    // Old close with no per-method notes: only the cash drawer diff is knowable.
    //   expected_cash = 1,000 + 4,000 = 5,000 ; counted = 4,915 → −85 cash.
    final closing = RegisterClosing(
      id: 's2',
      registerName: 'Caja 2',
      closedAt: DateTime(2026, 6, 9),
      closedByName: 'Cajero',
      openingAmount: 1000,
      cashSales: 4000,
      closingAmount: 4915,
      cardSales: 3000,
      transferSales: 0,
    );

    test('falls back to cash-only difference and flags missing breakdown', () {
      expect(closing.hasReportedBreakdown, isFalse);
      expect(closing.cashDifference, -85);
      expect(closing.cardDifference, 0);
      expect(closing.transferDifference, 0);
      expect(closing.netDifference, -85);
    });
  });
}
