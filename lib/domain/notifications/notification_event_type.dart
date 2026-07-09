import 'dashboard_notification.dart';

/// Canonical notification event types. The [key] values MUST match the
/// `event_type` column in `notification_preferences` and the keys used by the
/// push-notify Edge Function. Used by the settings screen (toggles) and the
/// in-app [NotificationService] (gating).
enum NotificationEventType {
  itemVoided(
    'item_voided',
    'Producto anulado',
    'Cuando se anula un producto de una orden.',
  ),
  cashClosed(
    'cash_closed',
    'Cierre de caja',
    'Cuando se cierra una caja.',
  ),
  cashMismatch(
    'cash_mismatch',
    'Caja descuadrada',
    'Cuando un cierre queda con faltante o sobrante.',
  ),
  tableOpened(
    'table_opened',
    'Nueva cuenta abierta',
    'Cuando se abre una mesa o cuenta (solo dentro de la app).',
  );

  const NotificationEventType(this.key, this.label, this.description);

  /// Stable identifier persisted in `notification_preferences.event_type`.
  final String key;

  /// Human label shown in the settings toggle.
  final String label;

  /// One-line explanation shown under the toggle.
  final String description;

  static NotificationEventType? fromKey(String key) {
    for (final t in NotificationEventType.values) {
      if (t.key == key) return t;
    }
    return null;
  }

  /// Maps an in-app [NotificationType] to its preference key, so the in-app
  /// stream can honor the same toggles. Returns null for types without a toggle.
  static String? keyForInApp(NotificationType type) {
    switch (type) {
      case NotificationType.itemVoided:
        return itemVoided.key;
      case NotificationType.cashClosed:
        return cashClosed.key;
      case NotificationType.tableOpened:
        return tableOpened.key;
    }
  }
}
