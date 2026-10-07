import 'package:flutter/material.dart';

enum NotificationType { itemVoided, orderVoided, cashClosed, tableOpened }

@immutable
class DashboardNotification {
  const DashboardNotification({
    required this.id,
    required this.type,
    required this.title,
    required this.message,
    required this.createdAt,
    this.isRead = false,
  });

  /// Id en la app de una fila de `notification_events`. Lo usan la lista y el
  /// banner, y FcmService con el `event_id` del push: con la app abierta el
  /// mismo aviso llega por Realtime y por FCM, y sale un solo banner.
  static String eventKey(String eventId) => 'evt_$eventId';

  final String id;
  final NotificationType type;
  final String title;
  final String message;
  final DateTime createdAt;
  final bool isRead;

  DashboardNotification markRead() => DashboardNotification(
        id: id,
        type: type,
        title: title,
        message: message,
        createdAt: createdAt,
        isRead: true,
      );
}
