import 'dart:async';
import 'dart:developer' as dev;

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/notifications/dashboard_notification.dart';

class NotificationService {
  NotificationService(this._client);

  final SupabaseClient _client;
  final _channels = <RealtimeChannel>[];
  final _controller = StreamController<DashboardNotification>.broadcast();
  final _seenIds = <String>{};

  Stream<DashboardNotification> get stream => _controller.stream;

  void subscribe(String businessId) {
    _dispose();
    _seenIds.clear();

    dev.log('[NotificationService] Subscribing for business: $businessId');

    // 1. order_items voided
    final itemsCh = _client.channel('notif_items_$businessId');
    itemsCh.onPostgresChanges(
      event: PostgresChangeEvent.update,
      schema: 'public',
      table: 'order_items',
      callback: (payload) {
        dev.log('[NotificationService] order_items UPDATE received');
        final rec = payload.newRecord;
        if (rec['status']?.toString() != 'void') return;
        final id = rec['id']?.toString() ?? '';
        if (!_seenIds.add('${id}_void')) return;
        _emit(DashboardNotification(
          id: '${id}_void_${DateTime.now().millisecondsSinceEpoch}',
          type: NotificationType.itemVoided,
          title: 'Producto eliminado',
          message: '${rec['qty'] ?? rec['quantity'] ?? 1} x ${rec['product_name'] ?? 'Producto'} fue eliminado.',
          createdAt: DateTime.now(),
        ));
      },
    );
    itemsCh.subscribe((status, [err]) {
      dev.log('[NotificationService] items channel status: $status, error: $err');
    });
    _channels.add(itemsCh);

    // 2. cash_register_sessions closed
    final cashCh = _client.channel('notif_cash_$businessId');
    cashCh.onPostgresChanges(
      event: PostgresChangeEvent.update,
      schema: 'public',
      table: 'cash_register_sessions',
      callback: (payload) {
        dev.log('[NotificationService] cash_register_sessions UPDATE received');
        final rec = payload.newRecord;
        if (rec['closed_at'] == null && rec['status']?.toString() != 'closed') return;
        final id = rec['id']?.toString() ?? '';
        if (!_seenIds.add('${id}_close')) return;
        _emit(DashboardNotification(
          id: '${id}_close_${DateTime.now().millisecondsSinceEpoch}',
          type: NotificationType.cashClosed,
          title: 'Cierre de caja',
          message: 'Se ha realizado un cierre de caja.',
          createdAt: DateTime.now(),
        ));
      },
    );
    cashCh.subscribe((status, [err]) {
      dev.log('[NotificationService] cash channel status: $status, error: $err');
    });
    _channels.add(cashCh);

    // 3. table_sessions opened (INSERT)
    final tablesCh = _client.channel('notif_tables_$businessId');
    tablesCh.onPostgresChanges(
      event: PostgresChangeEvent.insert,
      schema: 'public',
      table: 'table_sessions',
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'business_id',
        value: businessId,
      ),
      callback: (payload) {
        dev.log('[NotificationService] table_sessions INSERT received');
        final rec = payload.newRecord;
        final customer = rec['customer_name']?.toString();
        final origin = rec['origin']?.toString() ?? 'dine_in';
        final label = (customer != null && customer.trim().isNotEmpty)
            ? customer.trim()
            : _originLabel(origin);
        _emit(DashboardNotification(
          id: '${rec['id']}_open_${DateTime.now().millisecondsSinceEpoch}',
          type: NotificationType.tableOpened,
          title: 'Nueva cuenta abierta',
          message: '$label — ${_originLabel(origin)}.',
          createdAt: DateTime.now(),
        ));
      },
    );
    tablesCh.subscribe((status, [err]) {
      dev.log('[NotificationService] tables channel status: $status, error: $err');
    });
    _channels.add(tablesCh);
  }

  void _emit(DashboardNotification n) {
    if (!_controller.isClosed) {
      _controller.add(n);
    }
  }

  static String _originLabel(String origin) {
    switch (origin) {
      case 'dine_in': return 'Mesa';
      case 'quick': return 'Venta rápida';
      case 'delivery': return 'Delivery';
      case 'self_service': return 'Autoservicio';
      default: return 'Orden';
    }
  }

  void _dispose() {
    for (final ch in _channels) {
      _client.removeChannel(ch);
    }
    _channels.clear();
  }

  void dispose() {
    _dispose();
    _controller.close();
  }
}
