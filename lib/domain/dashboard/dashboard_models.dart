import 'package:flutter/material.dart';

import '../auth/admin_access_profile.dart';

enum SalesDateFilter { today, yesterday, week, month, lastMonth, last3Months, custom }

@immutable
class SalesByCategory {
  const SalesByCategory({required this.label, required this.amount});

  final String label;
  final double amount;
}

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
    required this.closedOrders,
    required this.salesByCategory,
    this.customRange,
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
  final List<TopProduct> topProducts;
  final List<CatalogItem> catalogItems;
  final List<LiveOrderItem> liveOrders;
  final List<LiveOrderItem> closedOrders;
  final List<SalesByCategory> salesByCategory;
  final double pendingAmount;
  final double previousDaySales;
  final List<HourlySale> hourlySales;
  final List<SalesByMethod> salesByMethod;
  final TopSeller? topSeller;
  final SalesDateFilter filter;
  final DateTimeRange? customRange;
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
    this.paymentMethodCode,
  });

  final String orderId;
  final double amount;
  final DateTime createdAt;
  final String? tableName;
  final String? customerName;
  final String? paymentMethodCode;
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
    this.zone,
    this.tableId,
    this.openedAt,
    this.peopleCount,
  });

  final String id;
  final String title;
  final String subtitle;
  final double total;
  final String status;
  final List<LiveChildItem> items;
  final String? zone;
  final String? tableId;
  final DateTime? openedAt;
  final int? peopleCount;
}

@immutable
class TableLayoutItem {
  const TableLayoutItem({
    required this.id,
    required this.label,
    required this.zoneId,
    required this.zoneName,
    this.capacity,
    this.shape,
    this.isActive = true,
  });

  final String id;
  final String label;
  final String zoneId;
  final String zoneName;
  final int? capacity;
  final String? shape;
  final bool isActive;
}

@immutable
class ZoneLayout {
  const ZoneLayout({
    required this.id,
    required this.name,
    required this.tables,
    this.sortIndex = 0,
  });

  final String id;
  final String name;
  final int sortIndex;
  final List<TableLayoutItem> tables;
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
    this.openedAt,
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
  final DateTime? openedAt;
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

@immutable
class NcfTypeSummary {
  const NcfTypeSummary({
    required this.type,
    required this.count,
    required this.total,
    this.firstNumber,
    this.lastNumber,
  });

  final String type;
  final int count;
  final double total;
  final String? firstNumber;
  final String? lastNumber;
}
