import 'package:flutter_test/flutter_test.dart';
import 'package:mango_dashboard/data/dashboard/sales_trend_aggregator.dart';
import 'package:mango_dashboard/domain/dashboard/dashboard_models.dart';

void main() {
  group('weekly', () {
    // 2026-05-04 is a Monday. Range covers weeks starting 05-04, 05-11, 05-18.
    final report = aggregateSalesTrend(
      granularity: TrendGranularity.week,
      rangeStart: DateTime(2026, 5, 4),
      rangeEnd: DateTime(2026, 5, 25), // exclusive → last day 05-24 (Sun)
      orderRows: [
        {'id': 'o1', 'closed_at': '2026-05-05T12:00:00'}, // Tue, week 05-04
        {'id': 'o2', 'closed_at': '2026-05-06T13:00:00'}, // Wed, week 05-04
        {'id': 'o3', 'closed_at': '2026-05-12T20:00:00'}, // Tue, week 05-11
        {'id': 'o4', 'closed_at': '2026-05-19T10:00:00'}, // Tue, week 05-18, unpaid
      ],
      payRows: [
        {'order_id': 'o1', 'amount': 100, 'change_amount': 0},
        {'order_id': 'o2', 'amount': 200, 'change_amount': 20}, // net 180
        {'order_id': 'o3', 'amount': 300, 'change_amount': 0},
        {'order_id': 'zz', 'amount': 999, 'change_amount': 0}, // unknown → ignored
      ],
    );

    test('produces one contiguous bucket per week', () {
      expect(report.buckets.map((b) => b.start).toList(), [
        DateTime(2026, 5, 4),
        DateTime(2026, 5, 11),
        DateTime(2026, 5, 18),
      ]);
    });

    test('sums payments net of change into the order\'s week', () {
      expect(report.buckets[0].total, closeTo(280, 1e-9)); // 100 + 180
      expect(report.buckets[0].orderCount, 2);
      expect(report.buckets[1].total, closeTo(300, 1e-9));
      expect(report.buckets[2].total, closeTo(0, 1e-9)); // counted, unpaid
      expect(report.buckets[2].orderCount, 1);
      expect(report.total, closeTo(580, 1e-9));
    });

    test('current vs previous expose the last two buckets', () {
      expect(report.currentTotal, closeTo(0, 1e-9)); // week 05-18 (in progress)
      expect(report.previousTotal, closeTo(300, 1e-9)); // week 05-11
    });

    test('heatmap keys sales by weekday and hour, peak preserved', () {
      final byKey = {for (final c in report.heat) c.weekday * 100 + c.hour: c.total};
      expect(byKey[DateTime.tuesday * 100 + 12], closeTo(100, 1e-9));
      expect(byKey[DateTime.wednesday * 100 + 13], closeTo(180, 1e-9));
      expect(byKey[DateTime.tuesday * 100 + 20], closeTo(300, 1e-9));
      final peak = report.heat.reduce((a, b) => a.total >= b.total ? a : b);
      expect(peak.weekday, DateTime.tuesday);
      expect(peak.hour, 20);
    });
  });

  group('monthly', () {
    final report = aggregateSalesTrend(
      granularity: TrendGranularity.month,
      rangeStart: DateTime(2026, 3, 1),
      rangeEnd: DateTime(2026, 6, 1), // Mar, Apr, May
      orderRows: [
        {'id': 'm1', 'closed_at': '2026-03-10T10:00:00'},
        {'id': 'm2', 'closed_at': '2026-05-02T10:00:00'},
      ],
      payRows: [
        {'order_id': 'm1', 'amount': 500, 'change_amount': 0},
        {'order_id': 'm2', 'amount': 700, 'change_amount': 0},
      ],
    );

    test('fills the empty middle month with a zero bucket', () {
      expect(report.buckets.map((b) => b.start).toList(), [
        DateTime(2026, 3, 1),
        DateTime(2026, 4, 1),
        DateTime(2026, 5, 1),
      ]);
      expect(report.buckets[0].total, closeTo(500, 1e-9));
      expect(report.buckets[1].total, closeTo(0, 1e-9)); // April, no sales
      expect(report.buckets[2].total, closeTo(700, 1e-9));
    });
  });

  test('empty input yields zeroed buckets and no heat', () {
    final report = aggregateSalesTrend(
      granularity: TrendGranularity.week,
      rangeStart: DateTime(2026, 5, 4),
      rangeEnd: DateTime(2026, 5, 11),
      orderRows: const [],
      payRows: const [],
    );
    expect(report.buckets.length, 1);
    expect(report.buckets.first.total, 0);
    expect(report.heat, isEmpty);
    expect(report.currentTotal, 0);
    expect(report.previousTotal, 0);
  });
}
