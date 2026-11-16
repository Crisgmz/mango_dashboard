/// Result of projecting a monthly sales goal from month-to-date actuals.
typedef GoalProgress = ({
  double progress, // actual / goal (can exceed 1)
  double projected, // run-rate projection for the full month
  double dailyTarget, // goal / daysTotal
  double dailyPace, // actual / daysElapsed (avg sold per working day so far)
  double remaining, // max(goal - actual, 0)
  bool onTrack, // projected >= goal
});

/// Projects month-end performance from [actual] sold in [daysElapsed] against a
/// [goal], using a simple run-rate over [daysTotal]. Both counts are working
/// days (see `monthWorkingDays`), so closed days don't dilute the pace. Pure
/// and unit-tested.
GoalProgress projectGoal({
  required double goal,
  required double actual,
  required int daysElapsed,
  required int daysTotal,
}) {
  final days = daysTotal < 1 ? 1 : daysTotal;
  final elapsed = daysElapsed < 1 ? 1 : (daysElapsed > days ? days : daysElapsed);

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
