import 'package:flutter/material.dart';

enum NotificationType { itemVoided, cashClosed, tableOpened }

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
