import 'package:flutter_test/flutter_test.dart';
import 'package:mango_dashboard/data/dashboard/goal_projection.dart';
import 'package:mango_dashboard/data/dashboard/working_days.dart';

void main() {
  // Octubre 2026: 31 días, el 1 es jueves → 5 jue/vie/sáb, 4 de los demás.
  group('monthWorkingDays', () {
    test('todos los días = días del calendario', () {
      final d = monthWorkingDays(year: 2026, month: 10, workingDays: kAllWeekdays, throughDay: 14);
      expect(d.total, 31);
      expect(d.elapsed, 14);
    });

    test('lunes a viernes solo cuenta días de semana', () {
      final d = monthWorkingDays(year: 2026, month: 10, workingDays: {1, 2, 3, 4, 5}, throughDay: 14);
      expect(d.total, 22);
      // 1–14 oct: jue 1, vie 2, lun 5 … vie 9, lun 12 … mié 14 → 10
      expect(d.elapsed, 10);
    });

    test('lunes a sábado', () {
      final d = monthWorkingDays(year: 2026, month: 10, workingDays: {1, 2, 3, 4, 5, 6});
      expect(d.total, 27);
      expect(d.elapsed, 27); // sin throughDay = mes completo (mes pasado)
    });

    test('hoy cerrado no suma días transcurridos', () {
      // Domingo 4 oct con lun–sáb: van jue 1, vie 2, sáb 3.
      final d = monthWorkingDays(year: 2026, month: 10, workingDays: {1, 2, 3, 4, 5, 6}, throughDay: 4);
      expect(d.elapsed, 3);
    });

    test('selección vacía se trata como todos los días', () {
      final d = monthWorkingDays(year: 2026, month: 2, workingDays: {});
      expect(d.total, 28);
    });

    test('proyección por día laborable', () {
      final d = monthWorkingDays(year: 2026, month: 10, workingDays: {1, 2, 3, 4, 5}, throughDay: 14);
      final p = projectGoal(goal: 0, actual: 100000, daysElapsed: d.elapsed, daysTotal: d.total);
      expect(p.dailyPace, closeTo(10000, 1e-9)); // 100,000 / 10
      expect(p.projected, closeTo(220000, 1e-9)); // 10,000 * 22
    });
  });

  group('workingDaysLabel', () {
    test('tramos y listas', () {
      expect(workingDaysLabel(kAllWeekdays), 'Todos los días');
      expect(workingDaysLabel({1, 2, 3, 4, 5}), 'Lunes a viernes');
      expect(workingDaysLabel({1, 2, 3, 4, 5, 6}), 'Lunes a sábado');
      expect(workingDaysLabel({4, 5, 6, 7, 1}), 'Jueves a lunes');
      expect(workingDaysLabel({6, 7}), 'Sábado y domingo');
      expect(workingDaysLabel({5}), 'Solo viernes');
      expect(workingDaysLabel({1, 3, 5}), 'Lun, Mié, Vie');
    });
  });
}
