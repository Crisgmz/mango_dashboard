/// Result of projecting a monthly sales goal from month-to-date actuals.
typedef GoalProgress = ({
  double progress, // actual / goal (can exceed 1)
  double projected, // run-rate projection for the full month
  double dailyTarget, // goal / daysInMonth
  double dailyPace, // actual / dayOfMonth (avg sold per day so far)
  double remaining, // max(goal - actual, 0)
  bool onTrack, // projected >= goal
});

/// Projects month-end performance from [actual] sold by [dayOfMonth] against a
/// [goal], using a simple run-rate. Pure and unit-tested.
GoalProgress projectGoal({
  required double goal,
  required double actual,
  required int dayOfMonth,
  required int daysInMonth,
}) {
  final days = daysInMonth < 1 ? 1 : daysInMonth;
  final elapsed = dayOfMonth < 1 ? 1 : (dayOfMonth > days ? days : dayOfMonth);

  final progress = goal > 0 ? actual / goal : 0.0;
  final dailyPace = actual / elapsed;
  final projected = dailyPace * days;
  final dailyTarget = goal / days;
  final remaining = goal - actual > 0 ? goal - actual : 0.0;
  final onTrack = goal > 0 && projected >= goal;

  return (
    progress: progress,
    projected: projected,
    dailyTarget: dailyTarget,
    dailyPace: dailyPace,
    remaining: remaining,
    onTrack: onTrack,
  );
}
