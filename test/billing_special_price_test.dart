import 'package:flutter_test/flutter_test.dart';
import 'package:mango_dashboard/domain/billing/billing_state.dart';

/// Precio especial de la suscripción: réplica de
/// `subscription_price_override_cents` (mangospos 20260915_0006).
void main() {
  Map<String, dynamic> row({
    int? overrideCents,
    String? overridePlanId = 'plan-pro',
    String? endsOn,
    String nextBilling = '2026-10-15',
    int listCents = 479900,
  }) => {
    'id': 'm1',
    'business_id': 'b1',
    'billing_status': 'active',
    'next_billing_date': nextBilling,
    'current_attempt_number': 0,
    'price_override_cents': overrideCents,
    'price_override_plan_id': overrideCents == null ? null : overridePlanId,
    'price_override_ends_on': endsOn,
    'plan': {
      'id': 'plan-pro',
      'code': 'pro',
      'name': 'Pro',
      'price_cents_monthly': listCents,
      'currency_code': 'DOP',
    },
  };

  test('sin precio especial cobra la lista', () {
    final s = BillingState.fromJson(row());
    expect(s.hasSpecialPrice, isFalse);
    expect(s.effectivePriceCents, 479900);
    expect(s.monthlyDiscount, 0);
  });

  test('precio especial vigente descuenta', () {
    final s = BillingState.fromJson(row(overrideCents: 300000));
    expect(s.hasSpecialPrice, isTrue);
    expect(s.effectivePriceCents, 300000);
    expect(s.effectivePriceMonthly, 3000.0);
    expect(s.monthlyDiscount, 1799.0);
  });

  test('amarrado al plan: otro plan cobra la lista', () {
    final s = BillingState.fromJson(
      row(overrideCents: 300000, overridePlanId: 'plan-basic'),
    );
    expect(s.hasSpecialPrice, isFalse);
    expect(s.effectivePriceCents, 479900);
  });

  test('vence el mismo día del cobro: todavía aplica (inclusive)', () {
    final s = BillingState.fromJson(
      row(overrideCents: 300000, endsOn: '2026-10-15'),
    );
    expect(s.effectivePriceCents, 300000);
  });

  test('vencido antes del próximo cobro: cobra la lista', () {
    final s = BillingState.fromJson(
      row(overrideCents: 300000, endsOn: '2026-10-14'),
    );
    expect(s.hasSpecialPrice, isFalse);
    expect(s.effectivePriceCents, 479900);
  });

  test('nunca por encima de la lista', () {
    final s = BillingState.fromJson(
      row(overrideCents: 300000, listCents: 250000),
    );
    expect(s.hasSpecialPrice, isFalse);
    expect(s.effectivePriceCents, 250000);
  });
}
