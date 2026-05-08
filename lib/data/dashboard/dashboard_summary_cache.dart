import 'package:flutter/foundation.dart';

import '../../domain/dashboard/dashboard_models.dart';

/// In-memory cache of the most recent [DashboardSummary] per account.
///
/// Used so that switching accounts shows the previous snapshot instantly while
/// a fresh fetch happens in the background. Cleared on logout per account.
class DashboardSummaryCache {
  final Map<String, _CacheEntry> _entries = {};

  /// Returns the cached summary for [accountKey] (typically the user email),
  /// or null if nothing is cached.
  DashboardSummary? get(String accountKey) => _entries[accountKey]?.summary;

  /// When the cached entry was stored, or null if absent.
  DateTime? cachedAt(String accountKey) => _entries[accountKey]?.cachedAt;

  /// Stores a summary snapshot. Replaces any prior entry for the same key.
  void put(String accountKey, DashboardSummary summary) {
    if (accountKey.isEmpty) return;
    _entries[accountKey] = _CacheEntry(summary: summary, cachedAt: DateTime.now());
  }

  void remove(String accountKey) => _entries.remove(accountKey);

  void clear() => _entries.clear();
}

@immutable
class _CacheEntry {
  const _CacheEntry({required this.summary, required this.cachedAt});
  final DashboardSummary summary;
  final DateTime cachedAt;
}
