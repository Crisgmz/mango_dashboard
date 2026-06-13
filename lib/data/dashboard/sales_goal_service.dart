import 'package:shared_preferences/shared_preferences.dart';

/// Stores the monthly sales goal per business + month. Persisted locally with
/// SharedPreferences (device-local); to share goals across devices this can be
/// backed by a Supabase `sales_goals` table later without changing callers.
class SalesGoalService {
  const SalesGoalService();

  String _key(String businessId, int year, int month) =>
      'sales_goal_${businessId}_${year}_$month';

  /// The goal for the given month, or null when unset (or non-positive).
  Future<double?> getGoal(String businessId, int year, int month) async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getDouble(_key(businessId, year, month));
    return (value == null || value <= 0) ? null : value;
  }

  /// Sets (or clears, when [amount] <= 0) the goal for the given month.
  Future<void> setGoal(String businessId, int year, int month, double amount) async {
    final prefs = await SharedPreferences.getInstance();
    final key = _key(businessId, year, month);
    if (amount <= 0) {
      await prefs.remove(key);
    } else {
      await prefs.setDouble(key, amount);
    }
  }
}
