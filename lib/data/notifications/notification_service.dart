import 'dart:async';
import 'dart:developer' as dev;

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/notifications/dashboard_notification.dart';
import '../../domain/notifications/notification_event_type.dart';

class NotificationService {
  NotificationService(this._client);

  /// El POS anota el motivo, el operador y el aprobador justo DESPUÉS de
  /// quitar/anular, y lo que se quita de la misma orden en 5 s se suma al
  /// mismo aviso (fn_notif_add_removed_items). Se espera a que eso termine
  /// antes de pedir el texto final; push-notify espera 6 s.
  static const _eventTextDelay = Duration(seconds: 7);

  final SupabaseClient _client;
  final _channels = <RealtimeChannel>[];
  final _controller = StreamController<DashboardNotification>.broadcast();
  final _seenIds = <String>{};
  // Sube en cada subscribe: un aviso que estaba esperando su texto cuando se
  // cambió de negocio se descarta en vez de caer en la lista del nuevo.
  int _generation = 0;
  // Caché user_id -> nombre para no resolver el mismo mesero en cada apertura.
  final _nameCache = <String, String>{};
  // Claves de evento que el usuario apagó para el negocio activo. Los emits con
  // un tipo deshabilitado se descartan. Se carga async en subscribe (modelo
  // opt-out: vacío = todo encendido).
  final _disabledTypes = <String>{};

  Stream<DashboardNotification> get stream => _controller.stream;

  void subscribe(String businessId) {
    _dispose();
    _generation++;
    _seenIds.clear();
    _disabledTypes.clear();
    unawaited(_loadDisabledPrefs(businessId));

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

    // 1. Productos quitados o reducidos después de cocina, cortesías,
    //    descuentos y anulaciones. La base decide qué avisa (triggers de
    //    notification_events, migraciones 20261007_0001 y 20261020_0003): los
    //    borradores y las mesas vacías no llegan aquí.
    final eventsCh = _client.channel('notif_events_$businessId');
    eventsCh.onPostgresChanges(
      event: PostgresChangeEvent.insert,
      schema: 'public',
      table: 'notification_events',
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'business_id',
        value: businessId,
      ),
      callback: (payload) {
        dev.log('[NotificationService] notification_events INSERT received');
        unawaited(_onNotificationEvent(payload.newRecord, _generation));
      },
    );
    eventsCh.subscribe((status, [err]) {
      dev.log('[NotificationService] events channel status: $status, error: $err');
    });
    _channels.add(eventsCh);

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

  /// Espera a que el POS termine de anotar motivo/operador y pide el texto
  /// final a `fn_notification_event_refresh` (el mismo que usa el push). Si el
  /// RPC falla, muestra el texto con el que se insertó la fila.
  Future<void> _onNotificationEvent(
    Map<String, dynamic> rec,
    int generation,
  ) async {
    final id = rec['id']?.toString() ?? '';
    final type = _typeForEventKey(rec['event_type']?.toString());
    if (id.isEmpty || type == null) return;
    if (!_seenIds.add(DashboardNotification.eventKey(id))) return;

    await Future<void>.delayed(_eventTextDelay);
    if (generation != _generation) return;

    var title = rec['title']?.toString() ?? '';
    var body = rec['body']?.toString() ?? '';
    try {
      final rows = await _client.rpc(
        'fn_notification_event_refresh',
        params: {'p_event_id': id},
      );
      final list = List<Map<String, dynamic>>.from(rows as List);
      if (list.isNotEmpty) {
        title = list.first['title']?.toString() ?? title;
        body = list.first['body']?.toString() ?? body;
      }
    } catch (e) {
      dev.log('[NotificationService] refresh event skipped: $e');
    }
    if (generation != _generation || title.isEmpty) return;

    _emit(DashboardNotification(
      id: DashboardNotification.eventKey(id),
      type: type,
      title: title,
      message: body,
      createdAt:
          DateTime.tryParse(rec['created_at']?.toString() ?? '') ?? DateTime.now(),
    ));
  }

  static NotificationType? _typeForEventKey(String? key) {
    switch (NotificationEventType.fromKey(key ?? '')) {
      case NotificationEventType.itemVoided:
        return NotificationType.itemVoided;
      case NotificationEventType.itemCourtesy:
        return NotificationType.itemCourtesy;
      case NotificationEventType.itemDiscount:
        return NotificationType.itemDiscount;
      case NotificationEventType.orderVoided:
        return NotificationType.orderVoided;
      default:
        return null;
    }
  }

  void _emit(DashboardNotification n) {
    final key = NotificationEventType.keyForInApp(n.type);
    if (key != null && _disabledTypes.contains(key)) return;
    if (!_controller.isClosed) {
      _controller.add(n);
    }
  }

  /// Carga las preferencias deshabilitadas del usuario para el negocio activo.
  /// Modelo opt-out: solo se guardan los eventos apagados. Degrada a "todo
  /// encendido" si falla (p. ej. migración aún sin aplicar).
  Future<void> _loadDisabledPrefs(String businessId) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return;
    try {
      final rows = await _client
          .from('notification_preferences')
          .select('event_type')
          .eq('user_id', userId)
          .eq('business_id', businessId)
          .eq('enabled', false);
      _disabledTypes
        ..clear()
        ..addAll({
          for (final row in List<Map<String, dynamic>>.from(rows as List))
            if (row['event_type'] != null) row['event_type'].toString(),
        });
    } catch (e) {
      dev.log('[NotificationService] prefs load skipped: $e');
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
