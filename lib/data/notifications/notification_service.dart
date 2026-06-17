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
  // Caché user_id -> nombre para no resolver el mismo mesero en cada apertura.
  final _nameCache = <String, String>{};

  Stream<DashboardNotification> get stream => _controller.stream;

  void subscribe(String businessId) {
    _dispose();
    _seenIds.clear();

    // Ensure the realtime socket carries the current access token. Postgres
    // Changes run RLS as the connected role; without this the socket may still
    // be treated as `anon` (e.g. after a silent session restore) and every
    // `TO authenticated` policy denies the subscription with error 42501
    // ("You do not have required role or permission to perform an operation").
    final token = _client.auth.currentSession?.accessToken;
    if (token != null) {
      _client.realtime.setAuth(token);
    }

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
      callback: (payload) async {
        dev.log('[NotificationService] table_sessions INSERT received');
        final rec = payload.newRecord;
        final customer = rec['customer_name']?.toString();
        final origin = rec['origin']?.toString() ?? 'dine_in';
        // Quién abrió la mesa: preferimos el mesero asignado y, si no hay,
        // quién la abrió (opened_by, siempre presente).
        final waiterId =
            (rec['waiter_user_id'] ?? rec['opened_by'])?.toString();
        final waiterName = await _resolveUserName(waiterId);

        final parts = <String>[
          (customer != null && customer.trim().isNotEmpty)
              ? customer.trim()
              : _originLabel(origin),
          if (waiterName != null && waiterName.isNotEmpty) 'Mesero: $waiterName',
        ];
        _emit(DashboardNotification(
          id: '${rec['id']}_open_${DateTime.now().millisecondsSinceEpoch}',
          type: NotificationType.tableOpened,
          title: 'Nueva cuenta abierta',
          message: '${parts.join(' · ')}.',
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

  /// Resuelve `user_id -> nombre` del mesero vía el RPC `fn_resolve_user_names`
  /// (SECURITY DEFINER, evita la RLS de `profiles`). Cachea el resultado para no
  /// repetir la consulta. Degrada a `null` si el RPC no está disponible (p. ej.
  /// migración aún sin aplicar), en cuyo caso la notificación omite el mesero.
  Future<String?> _resolveUserName(String? userId) async {
    if (userId == null || userId.isEmpty) return null;
    final cached = _nameCache[userId];
    if (cached != null) return cached;
    try {
      final rows = await _client.rpc(
        'fn_resolve_user_names',
        params: {'p_user_ids': [userId]},
      );
      for (final row in List<Map<String, dynamic>>.from(rows as List)) {
        final id = row['user_id']?.toString();
        final name = row['display_name']?.toString().trim();
        if (id != null && name != null && name.isNotEmpty) {
          _nameCache[id] = name;
          if (id == userId) return name;
        }
      }
    } catch (e) {
      dev.log('[NotificationService] resolve waiter name skipped: $e');
    }
    return null;
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
