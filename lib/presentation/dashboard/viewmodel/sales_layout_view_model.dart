import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/di/providers.dart';
import '../../../data/dashboard/sales_layout_service.dart';

/// Holds the current ordering of SalesView cards. Mutations persist to
/// SharedPreferences via [SalesLayoutService].
class SalesLayoutNotifier extends StateNotifier<List<SalesCard>> {
  SalesLayoutNotifier(this._ref) : super(kDefaultSalesLayout) {
    _load();
  }

  final Ref _ref;

  Future<void> _load() async {
    final order = await _ref.read(salesLayoutServiceProvider).loadOrder();
    if (mounted) state = order;
  }

  /// Move card at [oldIndex] to [newIndex] and persist.
  Future<void> reorder(int oldIndex, int newIndex) async {
    final list = List<SalesCard>.of(state);
    // ReorderableListView quirk: when moving down, newIndex is past the
    // current position because the row hasn't been removed yet.
    final adjusted = newIndex > oldIndex ? newIndex - 1 : newIndex;
    final card = list.removeAt(oldIndex);
    list.insert(adjusted, card);
    state = list;
    await _ref.read(salesLayoutServiceProvider).saveOrder(list);
  }

  Future<void> resetToDefault() async {
    state = List.of(kDefaultSalesLayout);
    await _ref.read(salesLayoutServiceProvider).resetToDefault();
  }
}

final salesLayoutProvider =
    StateNotifierProvider<SalesLayoutNotifier, List<SalesCard>>(
  (ref) => SalesLayoutNotifier(ref),
);
