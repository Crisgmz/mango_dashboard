import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/di/providers.dart';
import '../../../domain/notifications/dashboard_notification.dart';

class NotificationState {
  const NotificationState({this.notifications = const []});

  final List<DashboardNotification> notifications;

  int get unreadCount => notifications.where((n) => !n.isRead).length;

  NotificationState copyWith({List<DashboardNotification>? notifications}) {
    return NotificationState(notifications: notifications ?? this.notifications);
  }
}

class NotificationViewModel extends StateNotifier<NotificationState> {
  NotificationViewModel(this._ref) : super(const NotificationState());

  final Ref _ref;
  StreamSubscription<DashboardNotification>? _subscription;

  void subscribe(String businessId) {
    _subscription?.cancel();
    final service = _ref.read(notificationServiceProvider);
    service.subscribe(businessId);
    _subscription = service.stream.listen((notification) {
      state = state.copyWith(
        notifications: <DashboardNotification>[notification, ...state.notifications].take(50).toList(),
      );
    });
  }

  void markAllRead() {
    state = state.copyWith(
      notifications: state.notifications.map((n) => n.markRead()).toList(),
    );
  }

  void clear() {
    state = const NotificationState();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _ref.read(notificationServiceProvider).dispose();
    super.dispose();
  }
}

final notificationViewModelProvider =
    StateNotifierProvider<NotificationViewModel, NotificationState>(
  (ref) => NotificationViewModel(ref),
);
