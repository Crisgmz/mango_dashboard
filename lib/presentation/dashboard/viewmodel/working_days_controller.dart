import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/dashboard/working_days.dart';
import '../../../data/dashboard/working_days_service.dart';

/// Días laborables del negocio [businessId]. Arranca en "todos los días" y se
/// reemplaza con lo guardado en cuanto carga.
class WorkingDaysController extends StateNotifier<Set<int>> {
  WorkingDaysController(this._businessId, this._service) : super(kAllWeekdays) {
    _load();
  }

  final String _businessId;
  final WorkingDaysService _service;

  Future<void> _load() async {
    final days = await _service.load(_businessId);
    if (mounted) state = days;
  }

  Future<void> set(Set<int> days) async {
    state = normalizeWorkingDays(days);
    await _service.save(_businessId, state);
  }
}

final workingDaysProvider =
    StateNotifierProvider.family<WorkingDaysController, Set<int>, String>(
  (ref, businessId) => WorkingDaysController(businessId, const WorkingDaysService()),
);
