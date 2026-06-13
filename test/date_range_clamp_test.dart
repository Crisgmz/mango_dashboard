import 'package:flutter_test/flutter_test.dart';
import 'package:mango_dashboard/core/date/date_range_utils.dart';

void main() {
  // "today" reference used across the cases.
  final firstDate = DateTime(2023, 6, 11);
  final lastDate = DateTime(2026, 6, 10);

  group('clampInitialDateRange', () {
    test('caps an end that falls in the future (the "este mes" crash)', () {
      // Preset "este mes": June 2026, exclusive end → seed end 2026-06-30.
      final r = clampInitialDateRange(
        start: DateTime(2026, 6, 1),
        end: DateTime(2026, 6, 30),
        firstDate: firstDate,
        lastDate: lastDate,
      );
      expect(r.start, DateTime(2026, 6, 1));
      expect(r.end, lastDate); // pulled back to today
      expect(r.end.isAfter(lastDate), isFalse); // the picker's assertion holds
    });

    test('pulls a too-early start up to firstDate', () {
      final r = clampInitialDateRange(
        start: DateTime(2019, 1, 1),
        end: DateTime(2025, 1, 1),
        firstDate: firstDate,
        lastDate: lastDate,
      );
      expect(r.start, firstDate);
      expect(r.end, DateTime(2025, 1, 1));
    });

    test('leaves a valid past range untouched (only strips time)', () {
      final r = clampInitialDateRange(
        start: DateTime(2026, 5, 1, 9, 30),
        end: DateTime(2026, 5, 31, 23, 59),
        firstDate: firstDate,
        lastDate: lastDate,
      );
      expect(r.start, DateTime(2026, 5, 1));
      expect(r.end, DateTime(2026, 5, 31));
    });

    test('collapses an inverted seed to a single valid day', () {
      // Whole window is in the future relative to lastDate.
      final r = clampInitialDateRange(
        start: DateTime(2026, 7, 1),
        end: DateTime(2026, 7, 31),
        firstDate: firstDate,
        lastDate: lastDate,
      );
      expect(r.start, lastDate);
      expect(r.end, lastDate);
      expect(r.start.isAfter(r.end), isFalse);
    });

    test('always returns a range within bounds with start <= end', () {
      for (final seed in [
        [DateTime(2010, 1, 1), DateTime(2099, 1, 1)],
        [DateTime(2026, 6, 10), DateTime(2026, 6, 10)],
        [DateTime(2026, 6, 11), DateTime(2026, 6, 9)],
      ]) {
        final r = clampInitialDateRange(
          start: seed[0],
          end: seed[1],
          firstDate: firstDate,
          lastDate: lastDate,
        );
        expect(r.start.isBefore(firstDate), isFalse);
        expect(r.end.isAfter(lastDate), isFalse);
        expect(r.start.isAfter(r.end), isFalse);
      }
    });
  });
}
