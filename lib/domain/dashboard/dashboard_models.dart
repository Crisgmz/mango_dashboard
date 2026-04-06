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
    this.salesByMethod = const [],
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
  final List<SalesByMethod> salesByMethod;
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
class SalesByMethod {
  const SalesByMethod({required this.code, required this.amount});

  final String code;
  final double amount;

  String get label {
    switch (code) {
      case 'cash': return 'Efectivo';
      case 'card': return 'Tarjeta';
      case 'transfer': return 'Transferencia';
      default: return 'Otro';
    }
  }
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
    this.modifierGroups = const [],
  });

  final String name;
  final String status;
  final double? price;
  final String? category;
  final List<CatalogModifierGroup> modifierGroups;

  bool get hasModifiers => modifierGroups.isNotEmpty;
}

@immutable
class CatalogModifierGroup {
  const CatalogModifierGroup({
    required this.name,
    required this.selectionMode,
    this.modifiers = const [],
  });

  final String name;
  final String selectionMode;
  final List<CatalogModifier> modifiers;

  String get modeLabel {
    switch (selectionMode) {
      case 'extra': return 'Extra';
      case 'removal': return 'Remoción';
      default: return 'Modificador';
    }
  }
}

@immutable
class CatalogModifier {
  const CatalogModifier({
    required this.name,
    required this.priceDelta,
    this.isActive = true,
  });

  final String name;
  final double priceDelta;
  final bool isActive;
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
    this.extras = const [],
  });

  final String name;
  final double quantity;
  final double total;
  final List<String> extras;
}

// ── Cash Register (Caja) Models ──

@immutable
class CashRegisterSummary {
  const CashRegisterSummary({
    this.openRegisters = const [],
    this.closings = const [],
    this.totalRegisters = 0,
    this.activeRegisters = 0,
    this.topRegister,
  });

  final List<RegisterSession> openRegisters;
  final List<RegisterClosing> closings;
  final int totalRegisters;
  final int activeRegisters;
  final RegisterSession? topRegister;

  int get openRegistersCount => openRegisters.length;
  int get inactiveRegistersCount => (totalRegisters - activeRegisters).clamp(0, totalRegisters);
}

@immutable
class RegisterSession {
  const RegisterSession({
    required this.id,
    required this.registerName,
    required this.openedAt,
    required this.openedByName,
    this.closedAt,
    this.deviceName,
    this.openingAmount = 0,
    this.totalSales = 0,
    this.cashSales = 0,
    this.cardSales = 0,
    this.transferSales = 0,
    this.otherSales = 0,
    this.status = 'open',
  });

  final String id;
  final String registerName;
  final DateTime openedAt;
  final String openedByName;
  final DateTime? closedAt;
  final String? deviceName;
  final double openingAmount;
  final double totalSales;
  final double cashSales;
  final double cardSales;
  final double transferSales;
  final double otherSales;
  final String status;

  bool get isOpen => closedAt == null;
}

@immutable
class RegisterClosing {
  const RegisterClosing({
    required this.id,
    required this.registerName,
    required this.closedAt,
    required this.closedByName,
    this.deviceName,
    this.openingAmount = 0,
    this.closingAmount = 0,
    this.expectedAmount = 0,
    this.totalSales = 0,
    this.cashSales = 0,
    this.cardSales = 0,
    this.transferSales = 0,
    this.otherSales = 0,
    this.totalDeposits = 0,
    this.totalWithdrawals = 0,
    this.totalExpenses = 0,
  });

  final String id;
  final String registerName;
  final DateTime closedAt;
  final String closedByName;
  final String? deviceName;
  final double openingAmount;
  final double closingAmount;
  final double expectedAmount;
  final double totalSales;
  final double cashSales;
  final double cardSales;
  final double transferSales;
  final double otherSales;
  final double totalDeposits;
  final double totalWithdrawals;
  final double totalExpenses;

  double get difference => closingAmount - expectedAmount;
}
