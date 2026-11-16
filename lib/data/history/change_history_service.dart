import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/history/change_history_entry.dart';

/// Lee el historial de cambios del negocio por páginas. La RLS solo deja
/// leer a dueño y administradores; nadie puede escribir desde la app.
class ChangeHistoryService {
  ChangeHistoryService(this._client);

  final SupabaseClient _client;

  static const int pageSize = 50;

  Future<List<ChangeHistoryEntry>> loadPage({
    required String businessId,
    int offset = 0,
    List<String> tables = const [],
    String? action,
    String search = '',
  }) async {
    var query = _client
        .from('change_history')
        .select(
          'id, table_name, row_id, action, label, context, actor_name, '
          'changed_at, changes, source',
        )
        .eq('business_id', businessId);
    if (tables.isNotEmpty) query = query.inFilter('table_name', tables);
    if (action != null) query = query.eq('action', action);
    final term = _searchTerm(search);
    if (term.isNotEmpty) {
      query = query.or(
        'label.ilike.*$term*,context.ilike.*$term*,actor_name.ilike.*$term*',
      );
    }
    final rows = await query
        .order('changed_at', ascending: false)
        .order('id', ascending: false)
        .range(offset, offset + pageSize - 1);
    return (rows as List)
        .map((r) => ChangeHistoryEntry.fromJson(Map<String, dynamic>.from(r)))
        .toList(growable: false);
  }

  /// Quita lo que rompe el filtro `or` de PostgREST (comas, paréntesis,
  /// comodines).
  static String _searchTerm(String raw) =>
      raw.replaceAll(RegExp(r'[,()*%\\]'), ' ').trim();
}
