import 'dart:developer' as dev;

import 'package:supabase_flutter/supabase_flutter.dart';

/// Reads/writes per-user, per-business notification preferences
/// (`notification_preferences`). Opt-out model: only DISABLED events are stored;
/// anything without a row is considered enabled.
class NotificationPreferencesService {
  NotificationPreferencesService(this._client);

  final SupabaseClient _client;

  /// Returns the set of disabled event keys per business:
  /// `{ businessId: { 'item_voided', ... } }`. Empty map if signed out / on error
  /// (degrades to "everything enabled").
  Future<Map<String, Set<String>>> loadDisabled() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return {};
    try {
      final rows = await _client
          .from('notification_preferences')
          .select('business_id, event_type')
          .eq('user_id', userId)
          .eq('enabled', false);
      final map = <String, Set<String>>{};
      for (final row in List<Map<String, dynamic>>.from(rows as List)) {
        final business = row['business_id']?.toString();
        final event = row['event_type']?.toString();
        if (business == null || event == null) continue;
        map.putIfAbsent(business, () => <String>{}).add(event);
      }
      return map;
    } catch (e) {
      dev.log('notification_preferences load skipped: $e', name: 'notif_prefs');
      return {};
    }
  }

  /// Returns the disabled event keys for a single business.
  Future<Set<String>> loadDisabledForBusiness(String businessId) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return {};
    try {
      final rows = await _client
          .from('notification_preferences')
          .select('event_type')
          .eq('user_id', userId)
          .eq('business_id', businessId)
          .eq('enabled', false);
      return {
        for (final row in List<Map<String, dynamic>>.from(rows as List))
          if (row['event_type'] != null) row['event_type'].toString(),
      };
    } catch (e) {
      dev.log('notification_preferences load skipped: $e', name: 'notif_prefs');
      return {};
    }
  }

  /// Persists a single toggle. Upserts so repeated calls are safe.
  Future<void> setEnabled({
    required String businessId,
    required String eventType,
    required bool enabled,
  }) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return;
    await _client.from('notification_preferences').upsert({
      'user_id': userId,
      'business_id': businessId,
      'event_type': eventType,
      'enabled': enabled,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }, onConflict: 'user_id,business_id,event_type');
  }
}
