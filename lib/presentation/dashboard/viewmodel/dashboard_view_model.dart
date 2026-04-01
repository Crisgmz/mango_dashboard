import 'package:flutter/material.dart';

import '../../../domain/auth/admin_access_profile.dart';

@immutable
class DashboardState {
  const DashboardState({
    required this.isLoading,
    required this.profile,
    required this.kpis,
    required this.recentActivity,
    required this.catalogItems,
    required this.liveOrders,
  });

  const DashboardState.initial()
    : isLoading = false,
      profile = null,
      kpis = const [],
      recentActivity = const [],
      catalogItems = const [],
      liveOrders = const [];

  final bool isLoading;
  final AdminAccessProfile? profile;
  final List<KpiItem> kpis;
  final List<String> recentActivity;
  final List<CatalogItem> catalogItems;
  final List<LiveOrderItem> liveOrders;

  DashboardState copyWith({
    bool? isLoading,
    AdminAccessProfile? profile,
    List<KpiItem>? kpis,
    List<String>? recentActivity,
    List<CatalogItem>? catalogItems,
    List<LiveOrderItem>? liveOrders,
  }) {
    return DashboardState(
      isLoading: isLoading ?? this.isLoading,
      profile: profile ?? this.profile,
      kpis: kpis ?? this.kpis,
      recentActivity: recentActivity ?? this.recentActivity,
      catalogItems: catalogItems ?? this.catalogItems,
      liveOrders: liveOrders ?? this.liveOrders,
    );
  }
}

@immutable
class KpiItem {
  const KpiItem({required this.label, required this.value, required this.icon, required this.color});
  final String label;
  final String value;
  final IconData icon;
  final Color color;
}

@immutable
class CatalogItem {
  const CatalogItem({required this.name, required this.status});
  final String name;
  final String status;
}

@immutable
class LiveOrderItem {
  const LiveOrderItem({required this.title, required this.subtitle});
  final String title;
  final String subtitle;
}
