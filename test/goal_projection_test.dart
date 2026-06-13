import 'package:flutter_test/flutter_test.dart';
import 'package:mango_dashboard/data/dashboard/goal_projection.dart';

void main() {
  test('mid-month run-rate that beats the goal', () {
    final p = projectGoal(goal: 1500000, actual: 1180000, dayOfMonth: 20, daysInMonth: 30);
    expect(p.progress, closeTo(0.7867, 1e-3));
    expect(p.dailyPace, closeTo(59000, 1e-6)); // 1,180,000 / 20
    expect(p.projected, closeTo(1770000, 1e-6)); // 59,000 * 30
    expect(p.dailyTarget, closeTo(50000, 1e-6)); // 1,500,000 / 30
    expect(p.remaining, closeTo(320000, 1e-6));
    expect(p.onTrack, isTrue);
  });

  test('behind pace → not on track', () {
    final p = projectGoal(goal: 1500000, actual: 600000, dayOfMonth: 20, daysInMonth: 30);
    expect(p.projected, closeTo(900000, 1e-6)); // 30,000 * 30
    expect(p.onTrack, isFalse);
    expect(p.remaining, closeTo(900000, 1e-6));
  });

  test('goal already met → remaining is zero, on track', () {
    final p = projectGoal(goal: 1000000, actual: 1200000, dayOfMonth: 28, daysInMonth: 30);
    expect(p.remaining, 0);
    expect(p.progress, closeTo(1.2, 1e-9));
    expect(p.onTrack, isTrue);
  });

  test('no goal → safe zeros, not on track', () {
    final p = projectGoal(goal: 0, actual: 5000, dayOfMonth: 3, daysInMonth: 31);
    expect(p.progress, 0);
    expect(p.dailyTarget, 0);
    expect(p.onTrack, isFalse);
  });

  test('day 0 is clamped so projection never divides by zero', () {
    final p = projectGoal(goal: 100, actual: 10, dayOfMonth: 0, daysInMonth: 30);
    expect(p.dailyPace, closeTo(10, 1e-9)); // treated as day 1
    expect(p.projected, closeTo(300, 1e-9));
  });
}
