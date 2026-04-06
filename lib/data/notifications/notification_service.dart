import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/notifications/dashboard_notification.dart';

class NotificationService {
  NotificationService(this._client);

  final SupabaseClient _client;
  RealtimeChannel? _itemsChannel;
  RealtimeChannel? _cashChannel;

  final _controller = StreamController<DashboardNotification>.broadcast();

  Stream<DashboardNotification> get stream => _controller.stream;

  void subscribe(String businessId) {
    dispose();

    // Listen for order_items voided (status = 'void')
    _itemsChannel = _client.channel('items_void_$businessId')
      ..onPostgresChanges(
        event: PostgresChangeEvent.update,
        schema: 'public',
        table: 'order_items',
        callback: (payload) {
          final newRecord = payload.newRecord;
          final oldRecord = payload.oldRecord;
          final newStatus = newRecord['status']?.toString();
          final oldStatus = oldRecord['status']?.toString();
          if (newStatus == 'void' && oldStatus != 'void') {
            final productName = newRecord['product_name']?.toString() ?? 'Producto';
            final qty = newRecord['qty'] ?? newRecord['quantity'] ?? 1;
            _controller.add(DashboardNotification(
              id: '${newRecord['id']}_void_${DateTime.now().millisecondsSinceEpoch}',
              type: NotificationType.itemVoided,
              title: 'Producto eliminado',
              message: '$qty x $productName fue eliminado de una orden.',
              createdAt: DateTime.now(),
            ));
          }
        },
      )
      ..subscribe();

    // Listen for cash register session closures
    _cashChannel = _client.channel('cash_close_$businessId')
      ..onPostgresChanges(
        event: PostgresChangeEvent.update,
        schema: 'public',
        table: 'cash_register_sessions',
        callback: (payload) {
          final newRecord = payload.newRecord;
          final oldRecord = payload.oldRecord;
          final newClosedAt = newRecord['closed_at'];
          final oldClosedAt = oldRecord['closed_at'];
          if (newClosedAt != null && oldClosedAt == null) {
            _controller.add(DashboardNotification(
              id: '${newRecord['id']}_close_${DateTime.now().millisecondsSinceEpoch}',
              type: NotificationType.cashClosed,
              title: 'Cierre de caja',
              message: 'Se ha realizado un cierre de caja.',
              createdAt: DateTime.now(),
            ));
          }
        },
      )
      ..subscribe();
  }

  void dispose() {
    _itemsChannel?.unsubscribe();
    _cashChannel?.unsubscribe();
    _itemsChannel = null;
    _cashChannel = null;
  }
}
