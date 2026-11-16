import 'package:shared_preferences/shared_preferences.dart';

import 'working_days.dart';

/// Persiste los **días laborables** por negocio (en el teléfono, igual que la
/// meta de venta y la hora de corte). Default: todos los días.
class WorkingDaysService {
  const WorkingDaysService();

  String _key(String businessId) => 'working_days_$businessId';

  Future<Set<int>> load(String businessId) async {
    if (businessId.isEmpty) return kAllWeekdays;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_key(businessId));
    if (raw == null) return kAllWeekdays;
    return normalizeWorkingDays(raw.map((s) => int.tryParse(s) ?? 0));
  }

  Future<void> save(String businessId, Set<int> days) async {
    if (businessId.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final sorted = normalizeWorkingDays(days).toList()..sort();
    await prefs.setStringList(_key(businessId), sorted.map((d) => '$d').toList());
  }
}
