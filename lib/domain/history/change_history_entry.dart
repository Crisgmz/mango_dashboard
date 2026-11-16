/// Una línea del historial de cambios (tabla `change_history`, la llenan
/// triggers en la base de datos; la app solo la lee).
class ChangeHistoryEntry {
  const ChangeHistoryEntry({
    required this.id,
    required this.tableName,
    required this.rowId,
    required this.action,
    required this.label,
    required this.context,
    required this.actorName,
    required this.changedAt,
    required this.changes,
    this.source,
  });

  final int id;

  /// Tabla de origen: menu_items, taxes, order_items, orders, payments…
  final String tableName;
  final String rowId;

  /// create | update | delete | void
  final String action;

  /// Lo que cambió, legible: «Pollo frito», «Mesa 5», «B02».
  final String label;

  /// Lo segundo en vínculos y cuentas: «ITBIS 18%», «Cajero», la mesa.
  final String context;

  /// Nombre de quien lo hizo, tal como era al momento del cambio.
  final String actorName;
  final DateTime changedAt;

  /// update: {campo: [antes, después]} · create/delete/void: la fila.
  final Map<String, dynamic> changes;

  /// request.path de PostgREST ('/menu_items', '/rpc/fn_x'); null = interno.
  final String? source;

  factory ChangeHistoryEntry.fromJson(Map<String, dynamic> json) {
    final raw = json['changes'];
    return ChangeHistoryEntry(
      id: (json['id'] as num).toInt(),
      tableName: json['table_name']?.toString() ?? '',
      rowId: json['row_id']?.toString() ?? '',
      action: json['action']?.toString() ?? 'update',
      label: json['label']?.toString() ?? '',
      context: json['context']?.toString() ?? '',
      actorName: json['actor_name']?.toString() ?? '',
      changedAt:
          DateTime.tryParse(json['changed_at']?.toString() ?? '')?.toLocal() ??
          DateTime.now(),
      changes: raw is Map ? Map<String, dynamic>.from(raw) : const {},
      source: json['source']?.toString(),
    );
  }
}
