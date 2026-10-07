import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mango_dashboard/domain/billing/billing_charge.dart';
import 'package:mango_dashboard/domain/billing/billing_refund.dart';
import 'package:mango_dashboard/presentation/billing/widgets/charge_history_list.dart';

/// Reembolsos de la suscripción en la pantalla del dueño.
void main() {
  BillingCharge charge(String id, int cents, {String at = '2026-09-16T07:00:01Z'}) =>
      BillingCharge.fromJson({
        'id': id,
        'order_number': 'MP$id',
        'attempt_number': 1,
        'amount_cents': cents,
        'status': 'approved',
        'attempted_at': at,
        'completed_at': at,
      });

  BillingRefund refund(String chargeId, int cents, String at) =>
      BillingRefund.fromJson({
        'id': 'r-$chargeId-$cents',
        'charge_id': chargeId,
        'amount_cents': cents,
        'currency_code': 'DOP',
        'refunded_at': at,
      });

  test('reembolso parcial: neto = cobrado − reembolsado', () {
    final charges = attachRefunds(
      [charge('sep', 479999), charge('ago', 300000, at: '2026-08-16T07:00:01Z')],
      [refund('sep', 179999, '2026-09-17T15:00:00Z')],
    );
    final sep = charges.first;
    expect(sep.hasRefund, isTrue);
    expect(sep.isFullyRefunded, isFalse);
    expect(sep.refunded, 1799.99);
    expect(sep.netAmount, 3000.0);
    expect(charges.last.hasRefund, isFalse);
  });

  test('varios reembolsos que suman el total: reembolsado completo', () {
    final c = attachRefunds([charge('sep', 479999)], [
      refund('sep', 179999, '2026-09-17T15:00:00Z'),
      refund('sep', 300000, '2026-09-18T15:00:00Z'),
    ]).single;
    expect(c.isFullyRefunded, isTrue);
    expect(c.netAmount, 0.0);
  });

  test('reembolso de un cobro fuera del historial se ignora', () {
    final charges = attachRefunds(
      [charge('sep', 479999)],
      [refund('viejo', 1000, '2026-01-01T00:00:00Z')],
    );
    expect(charges.single.hasRefund, isFalse);
  });

  test('aviso: el reembolso más reciente dentro de 30 días', () {
    final charges = attachRefunds(
      [charge('sep', 479999), charge('jul', 300000, at: '2026-07-16T07:00:01Z')],
      [
        refund('jul', 5000, '2026-07-20T12:00:00Z'), // viejo
        refund('sep', 179999, '2026-09-17T15:00:00Z'),
      ],
    );
    final now = DateTime.parse('2026-09-20T12:00:00Z');
    final recent = latestRecentRefund(charges, now: now);
    expect(recent?.refund.amountCents, 179999);
    expect(recent?.charge.id, 'sep');

    // 40 días después ya no se avisa arriba (queda en el historial).
    expect(
      latestRecentRefund(charges, now: DateTime.parse('2026-10-27T12:00:00Z')),
      isNull,
    );
  });

  testWidgets('historial muestra el reembolso y lo pagado', (tester) async {
    final charges = attachRefunds(
      [charge('sep', 479999)],
      [refund('sep', 179999, '2026-09-17T15:00:00Z')],
    );
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: ChargeHistoryList(charges: charges))),
    );
    expect(find.text('RD\$ 4,799.99'), findsOneWidget);
    expect(
      find.textContaining('Reembolsado RD\$ 1,799.99 el 17/09/2026 · pagaste RD\$ 3,000.00'),
      findsOneWidget,
    );
    expect(find.text('Aprobado'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
