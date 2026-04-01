import 'package:flutter/material.dart';

import '../auth/admin_access_profile.dart';

enum SalesDateFilter { today, yesterday, week, month, lastMonth, last3Months }

@immutable
class DashboardSummary {
  const DashboardSummary({
    required this.profile,
    required this.totalSales,
    required this.totalTickets,
    required this.averageTicket,
    required this.activeOrders,
    required this.topProducts,
    required this.catalogItems,
    required this.liveOrders,
    this.pendingAmount = 0,
    this.previousDaySales = 0,
    this.hourlySales = const [],
    this.topSeller,
    this.filter = SalesDateFilter.month,
    this.tickets = const [],
    this.pendingTables = const [],
  });

  final AdminAccessProfile profile;
  final double totalSales;
  final int totalTickets;
  final double averageTicket;
  final int activeOrders;
  final double pendingAmount;
  final double previousDaySales;
  final List<HourlySale> hourlySales;
  final TopSeller? topSeller;
  final List<TopProduct> topProducts;
  final List<CatalogItem> catalogItems;
  final List<LiveOrderItem> liveOrders;
  final SalesDateFilter filter;
  final List<TicketItem> tickets;
  final List<PendingTable> pendingTables;

  double get salesChangePercent {
    if (previousDaySales == 0) return 0;
    return ((totalSales - previousDaySales) / previousDaySales) * 100;
  }
}

@immutable
class HourlySale {
  const HourlySale({required this.hour, required this.amount});

  final int hour;
  final double amount;
}

@immutable
class TopSeller {
  const TopSeller({
    required this.name,
    required this.totalSales,
    required this.orderCount,
  });

  final String name;
  final double totalSales;
  final int orderCount;
}

@immutable
class TopProduct {
  const TopProduct({required this.label, required this.amount, required this.quantity});

  final String label;
  final double amount;
  final double quantity;
}

@immutable
class CatalogItem {
  const CatalogItem({
    required this.name,
    required this.status,
    required this.price,
    required this.category,
  });

  final String name;
  final String status;
  final double? price;
  final String? category;
}

@immutable
class TicketItem {
  const TicketItem({
    required this.orderId,
    required this.amount,
    required this.createdAt,
    this.tableName,
    this.customerName,
  });

  final String orderId;
  final double amount;
  final DateTime createdAt;
  final String? tableName;
  final String? customerName;
}

@immutable
class PendingTable {
  const PendingTable({
    required this.tableName,
    required this.customerName,
    required this.total,
    required this.status,
    required this.itemCount,
  });

  final String tableName;
  final String customerName;
  final double total;
  final String status;
  final int itemCount;
}

@immutable
class LiveOrderItem {
  const LiveOrderItem({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.total,
    required this.status,
    this.items = const [],
  });

  final String id;
  final String title;
  final String subtitle;
  final double total;
  final String status;
  final List<LiveChildItem> items;
}

@immutable
class LiveChildItem {
  const LiveChildItem({
    required this.name,
    required this.quantity,
    required this.total,
  });

  final String name;
  final double quantity;
  final double total;
}
