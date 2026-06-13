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
    this.waiterPerformance = const [],
    this.cashierPerformance = const [],
    this.periodStart,
    this.periodEnd,
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
  final List<WaiterPerformance> waiterPerformance;
  final List<CashierPerformance> cashierPerformance;

  /// Inclusive lower bound of the period this summary represents (UTC).
  /// Drill-down views (e.g. waiter/cashier detail) reuse it to query rows
  /// for exactly the same window the user is looking at.
  final DateTime? periodStart;

  /// Exclusive upper bound of the period.
  final DateTime? periodEnd;

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

/// Customer aggregated across all payments in the period — grouped by
/// RNC when available, falling back to a normalized name when not. Used by
/// the customer analytics screen to surface recurring vs new customers.
@immutable
class CustomerSummary {
  const CustomerSummary({
    required this.customerKey,
    required this.displayName,
    required this.totalSpent,
    required this.visitCount,
    required this.firstVisit,
    required this.lastVisit,
    this.rnc,
  });

  /// Stable identifier within the period — either the RNC (preferred) or
  /// the normalized lower-case name when no RNC is captured.
  final String customerKey;

  /// Prettiest name available for display.
  final String displayName;

  /// Nullable: anonymous-but-named customers won't have one.
  final String? rnc;

  final double totalSpent;
  final int visitCount;
  final DateTime firstVisit;
  final DateTime lastVisit;

  double get averageTicket => visitCount == 0 ? 0 : totalSpent / visitCount;

  /// True when first and only visit fell inside the period — proxy for
  /// "new customer" (we don't have full history here).
  bool get isFirstTime => visitCount == 1 && firstVisit == lastVisit;

  /// True when there's more than one visit in the period.
  bool get isRecurring => visitCount > 1;

  int daysSinceLastVisit(DateTime now) {
    return now.difference(lastVisit).inDays;
  }
}

/// One visit (= one payment row) used in the customer drill-down.
@immutable
class CustomerVisit {
  const CustomerVisit({
    required this.orderId,
    required this.amount,
    required this.createdAt,
    this.tableLabel,
    this.paymentMethodCode,
  });

  final String orderId;
  final double amount;
  final DateTime createdAt;
  final String? tableLabel;
  final String? paymentMethodCode;
}

/// Single modifier (extra/option, e.g. "Extra queso") aggregated across all
/// orders in the period. Loaded lazily by the modifiers report screen.
@immutable
class ModifierSummary {
  const ModifierSummary({
    required this.name,
    required this.count,
    required this.revenue,
  });

  /// Verbatim from `order_item_modifiers.name`.
  final String name;

  /// Total quantity of this modifier across all orders in the period (sum
  /// of `qty`, defaulting to 1 per row when null).
  final double count;

  /// Sum of `(price_delta or 0) * qty` for every occurrence — i.e. the
  /// money this modifier added to the period's revenue.
  final double revenue;
}

/// One calendar day inside a "Ventas por día" report. Gross sales = sum of the
/// day's payments (net of change) for orders closed that day.
@immutable
class DailySalesEntry {
  const DailySalesEntry({
    required this.date,
    required this.total,
    required this.orderCount,
  });

  /// Local calendar day (time component is midnight).
  final DateTime date;

  /// Gross sales for the day (taxes included).
  final double total;
  final int orderCount;
}

/// One tax/charge line aggregated over the range, by its name as configured in
/// the business (`order_item_tax_lines.tax_name`). Whatever taxes exist show up
/// here — nothing is hardcoded.
@immutable
class TaxLineTotal {
  const TaxLineTotal({required this.name, required this.amount, this.rate});
  final String name;
  final double amount;

  /// Representative rate (fraction, e.g. 0.18) when consistent across lines.
  final double? rate;
}

/// "Ventas por día" report over a date range: per-day gross sales plus the tax
/// breakdown of the whole range. Gross comes from payments; taxes from
/// `order_item_tax_lines`, so `netTotal = grossTotal − Σ taxes`.
@immutable
class DailySalesReport {
  const DailySalesReport({
    this.days = const [],
    this.grossTotal = 0,
    this.taxes = const [],
    this.orderCount = 0,
  });

  final List<DailySalesEntry> days;

  /// Gross sales across the range (taxes/charges included).
  final double grossTotal;

  /// Each tax/charge applied in the range, by name. Empty when none recorded.
  final List<TaxLineTotal> taxes;

  final int orderCount;

  double get taxTotal => taxes.fold<double>(0, (s, t) => s + t.amount);

  /// Sales without any taxes/charges.
  double get netTotal => grossTotal - taxTotal;
}

/// Aggregated sales attributed to a single waiter for the current period.
/// Sourced from `payments` joined with `orders → table_sessions.waiter_user_id`.
@immutable
class WaiterPerformance {
  const WaiterPerformance({
    required this.userId,
    required this.name,
    required this.totalSales,
    required this.ticketCount,
    required this.tablesCount,
  });

  final String userId;
  final String name;
  final double totalSales;
  final int ticketCount;
  final int tablesCount;

  double get averageTicket => ticketCount == 0 ? 0 : totalSales / ticketCount;
}

/// Aggregated sales processed by a single cashier — derived from
/// `payments.processed_by` over the selected period.
@immutable
class CashierPerformance {
  const CashierPerformance({
    required this.userId,
    required this.name,
    required this.totalSales,
    required this.ticketCount,
    required this.tablesCount,
  });

  final String userId;
  final String name;
  final double totalSales;
  final int ticketCount;
  final int tablesCount;

  double get averageTicket => ticketCount == 0 ? 0 : totalSales / ticketCount;
}

/// Loss-prevention snapshot for the period — totals + counts of voided
/// items, cancelled payments, and discounts applied. Lightweight numbers
/// computed alongside the rest of the dashboard summary; the heavy lists
/// live in [AuditDetail] and are loaded on demand.
@immutable
class AuditSummary {
  const AuditSummary({
    this.voidedAmount = 0,
    this.voidedItemsCount = 0,
    this.cancelledAmount = 0,
    this.cancelledPaymentsCount = 0,
    this.discountsAmount = 0,
    this.discountsAppliedCount = 0,
  });

  final double voidedAmount;
  final int voidedItemsCount;
  final double cancelledAmount;
  final int cancelledPaymentsCount;
  final double discountsAmount;
  final int discountsAppliedCount;

  bool get isEmpty =>
      voidedItemsCount == 0 &&
      cancelledPaymentsCount == 0 &&
      discountsAppliedCount == 0;

  double get totalLoss => voidedAmount + cancelledAmount + discountsAmount;
}

/// Detail breakdown loaded lazily when the user taps the audit card.
@immutable
class AuditDetail {
  const AuditDetail({
    this.voidedItems = const [],
    this.cancelledPayments = const [],
    this.discountedOrders = const [],
  });

  final List<VoidedItem> voidedItems;
  final List<CancelledPayment> cancelledPayments;
  final List<DiscountedOrder> discountedOrders;
}

@immutable
class VoidedItem {
  const VoidedItem({
    required this.orderItemId,
    required this.productName,
    required this.amount,
    required this.quantity,
    required this.createdAt,
    this.tableLabel,
    this.customerName,
    this.waiterName,
  });

  final String orderItemId;
  final String productName;
  final double amount;
  final double quantity;
  final DateTime createdAt;
  final String? tableLabel;
  final String? customerName;
  final String? waiterName;
}

@immutable
class CancelledPayment {
  const CancelledPayment({
    required this.paymentId,
    required this.amount,
    required this.createdAt,
    this.status = 'cancelled',
    this.methodCode,
    this.cashierName,
    this.tableLabel,
  });

  final String paymentId;
  final double amount;
  final DateTime createdAt;

  /// 'void' or 'cancelled' — kept verbatim from the row so we can chip it.
  final String status;
  final String? methodCode;
  final String? cashierName;
  final String? tableLabel;
}

@immutable
class DiscountedOrder {
  const DiscountedOrder({
    required this.orderId,
    required this.discount,
    required this.total,
    required this.createdAt,
    this.tableLabel,
    this.customerName,
    this.waiterName,
  });

  final String orderId;
  final double discount;
  final double total;
  final DateTime createdAt;
  final String? tableLabel;
  final String? customerName;
  final String? waiterName;

  /// Discount as a fraction of (discount + total) — total in the orders table
  /// is already net of discount in this schema.
  double get percent {
    final gross = total + discount;
    if (gross == 0) return 0;
    return discount / gross;
  }
}

/// Single session/table row used by the drill-down view that lists which
/// mesas a waiter served (or whose payments a cashier processed) in the period.
@immutable
class PersonSession {
  const PersonSession({
    required this.sessionId,
    required this.tableLabel,
    required this.openedAt,
    this.closedAt,
    this.zoneName,
    this.customerName,
    this.peopleCount,
    this.total = 0,
    this.paymentMethodCode,
    this.origin,
  });

  final String sessionId;
  final String tableLabel;
  final String? zoneName;
  final DateTime openedAt;
  final DateTime? closedAt;
  final String? customerName;
  final int? peopleCount;
  final double total;

  /// For the cashier drill-down: which method they processed for this row.
  final String? paymentMethodCode;

  /// Origin of the session (dine_in / quick / manual / delivery / self_service).
  final String? origin;

  bool get isOpen => closedAt == null;
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
    this.difference = 0,
    this.notes,
    this.reportedCash,
    this.reportedCard,
    this.reportedTransfer,
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

  /// Cash-only difference persisted by `fn_close_cash_session`
  /// (`end_amount − expected_cash`). This is a cash-drawer reconciliation value,
  /// NOT the net difference across all payment methods. Label it "Dif. efectivo".
  final double difference;

  /// Raw `cash_register_sessions.notes` string. Holds the cashier-reported
  /// breakdown per method. May be null on old sessions.
  final String? notes;

  /// Cashier-reported amounts parsed from [notes]. Null when not present.
  /// Reported cash also lives structurally in [closingAmount] (`end_amount`).
  final double? reportedCash;
  final double? reportedCard;
  final double? reportedTransfer;

  // ---------------------------------------------------------------------------
  // Cash-close reconciliation — derived purely from structured data + the
  // reported values parsed from notes. No RPC needed:
  //   expectedCash = end_amount − difference   (inverse of fn_close_cash_session)
  //   expectedCard = card sales, expectedTransfer = transfer sales
  //   reportedCash = end_amount (or notes), reportedCard/transfer = notes
  //   NET difference = reportedTotal − expectedTotal = Σ per-method differences.
  // ---------------------------------------------------------------------------

  /// Cash-only difference recomputed locally from the drawer flow. Kept for the
  /// Reporte Z receipt (`CAJA EN EFECTIVO`).
  double get cashDrawerDifference => closingAmount - expectedAmount;

  /// Expected cash in the drawer: `apertura + ventas efectivo + depósitos −
  /// retiros − gastos`. Mirrors `fn_get_cash_session_summary.expected_cash` and
  /// the Reporte Z "Esperado" line — independent of the persisted `difference`.
  double get expectedCash =>
      openingAmount + cashSales + totalDeposits - totalWithdrawals - totalExpenses;
  double get expectedCard => cardSales;
  double get expectedTransfer => transferSales;
  double get expectedTotal => expectedCash + expectedCard + expectedTransfer;

  /// Reported (counted) cash: from notes when present, else `end_amount`.
  double get reportedCashResolved => reportedCash ?? closingAmount;

  /// Reported card/transfer: from notes when present; otherwise assume the
  /// cashier reported the expected (electronic) amount, i.e. zero discrepancy.
  double get reportedCardResolved => reportedCard ?? cardSales;
  double get reportedTransferResolved => reportedTransfer ?? transferSales;

  double get reportedTotal =>
      reportedCashResolved + reportedCardResolved + reportedTransferResolved;

  double get cashDifference => reportedCashResolved - expectedCash;
  double get cardDifference => reportedCardResolved - expectedCard;
  double get transferDifference => reportedTransferResolved - expectedTransfer;

  /// NET difference across all methods (the headline). Positive = surplus.
  double get netDifference => reportedTotal - expectedTotal;

  /// Whether the cashier reported a per-method breakdown (card/transfer) — i.e.
  /// the difference can be more than just the cash drawer.
  bool get hasReportedBreakdown => reportedCard != null || reportedTransfer != null;
}

/// A single cash-drawer movement (deposit / withdrawal / expense / sale).
/// Used to drill into a closing's breakdown cards and read each note.
@immutable
class CashTransactionEntry {
  const CashTransactionEntry({
    required this.id,
    required this.type,
    required this.amount,
    this.description,
    this.createdAt,
    this.relatedOrderId,
  });

  /// `sale | deposit | withdrawal | expense`.
  final String type;
  final String id;
  final double amount;
  final String? description;
  final DateTime? createdAt;
  final String? relatedOrderId;
}

/// Fully reconciled view of a cash closing — the dashboard equivalent of the
/// POS "cierre de caja" summary. The reconciliation numbers live on [closing]
/// (derived from structured data + notes); this adds the individual cash
/// movements (for the interactive drill-down) and the forced-close note.
///
/// The headline difference is the NET difference across all methods
/// ([RegisterClosing.netDifference]), not the cash-only drawer difference.
@immutable
class CashCloseDetail {
  const CashCloseDetail({
    required this.closing,
    this.transactionCount = 0,
    this.forcedCloseNote,
    this.transactions = const [],
  });

  final RegisterClosing closing;
  final int transactionCount;
  final String? forcedCloseNote;
  final List<CashTransactionEntry> transactions;

  // Flow / sales — read straight off the closing aggregates.
  double get startAmount => closing.openingAmount;
  double get cashSales => closing.cashSales;
  double get cardSales => closing.cardSales;
  double get transferSales => closing.transferSales;
  double get totalSales => closing.totalSales;
  double get totalDeposits => closing.totalDeposits;
  double get totalWithdrawals => closing.totalWithdrawals;
  double get totalExpenses => closing.totalExpenses;

  // Reconciliation — delegated to the closing (single source of truth).
  double get expectedCash => closing.expectedCash;
  double get expectedCard => closing.expectedCard;
  double get expectedTransfer => closing.expectedTransfer;
  double get expectedTotalResolved => closing.expectedTotal;

  double get reportedCash => closing.reportedCashResolved;
  double get reportedCard => closing.reportedCardResolved;
  double get reportedTransfer => closing.reportedTransferResolved;
  double get reportedTotal => closing.reportedTotal;

  double get netDifference => closing.netDifference;
  double get diffCash => closing.cashDifference;
  double get diffCard => closing.cardDifference;
  double get diffTransfer => closing.transferDifference;

  /// Persisted cash-only drawer difference (gaveta). Label "Dif. efectivo".
  double get cashDrawerDifference =>
      closing.difference != 0 ? closing.difference : closing.cashDrawerDifference;

  bool get hasReported => closing.hasReportedBreakdown;
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

/// One NCF type aggregated for the fiscal report: count, amounts and the
/// issued-number range.
@immutable
class FiscalTypeSummary {
  const FiscalTypeSummary({
    required this.type,
    required this.count,
    required this.subtotal,
    required this.itbis,
    required this.total,
    this.firstNumber,
    this.lastNumber,
  });
  final String type;
  final int count;
  final double subtotal;
  final double itbis;
  final double total;
  final String? firstNumber;
  final String? lastNumber;
}

/// Fiscal report for a period: NCF by type, the real tax breakdown (ITBIS,
/// propina, …) and the consolidated subtotal/total. NCF/totals come from
/// `fiscal_documents`; the tax breakdown from `order_item_tax_lines`.
@immutable
class FiscalReport {
  const FiscalReport({
    this.byType = const [],
    this.taxes = const [],
    this.subtotal = 0,
    this.itbis = 0,
    this.total = 0,
    this.documentCount = 0,
    this.cancelledCount = 0,
  });

  /// Active NCF grouped by type, sorted by total desc.
  final List<FiscalTypeSummary> byType;

  /// Real taxes/charges applied in the period, by name (sorted by amount).
  final List<TaxLineTotal> taxes;

  final double subtotal;
  final double itbis;
  final double total;

  /// Active fiscal documents in the period.
  final int documentCount;

  /// Documents cancelled (anulados) in the period.
  final int cancelledCount;

  /// All taxes/charges actually collected in the period (ITBIS, propina, …),
  /// summed from the real `order_item_tax_lines`. This — not a fixed rate or the
  /// stored `itbis_amount` — is what the report shows as "impuestos recaudados".
  double get taxTotal => taxes.fold<double>(0, (s, t) => s + t.amount);
}

/// Granularity for the sales-trend report.
enum TrendGranularity { week, month }

/// One time bucket of the sales-trend report: an ISO week (starting Monday) or
/// a calendar month.
@immutable
class TrendBucket {
  const TrendBucket({
    required this.start,
    required this.total,
    required this.orderCount,
  });

  /// Local date-only start of the bucket (Monday for weeks, the 1st for months).
  final DateTime start;
  final double total;
  final int orderCount;
}

/// One weekday×hour cell of the sales heatmap.
@immutable
class HeatCell {
  const HeatCell({
    required this.weekday,
    required this.hour,
    required this.total,
  });

  /// 1 = Monday … 7 = Sunday (matches [DateTime.weekday]).
  final int weekday;

  /// Local hour, 0 … 23.
  final int hour;
  final double total;
}

/// Sales-trend report: gross sales bucketed over time (for the trend chart)
/// plus a weekday×hour heatmap of the same range. Gross comes from payments net
/// of change, consistent with the other reports.
@immutable
class SalesTrendReport {
  const SalesTrendReport({
    this.buckets = const [],
    this.heat = const [],
    this.granularity = TrendGranularity.week,
  });

  final List<TrendBucket> buckets;
  final List<HeatCell> heat;
  final TrendGranularity granularity;

  double get total => buckets.fold<double>(0, (s, b) => s + b.total);

  /// Total of the most recent bucket (the one currently in progress).
  double get currentTotal => buckets.isEmpty ? 0 : buckets.last.total;

  /// Total of the bucket before the current one — the comparison baseline.
  double get previousTotal =>
      buckets.length < 2 ? 0 : buckets[buckets.length - 2].total;
}

/// A named sales bucket used by the operations report for zones, origins and
/// tables: a label plus its gross sales and order count.
@immutable
class NamedSales {
  const NamedSales({required this.name, required this.total, required this.orderCount});
  final String name;
  final double total;
  final int orderCount;
}

/// Operations report for a period: where and how sales happen (by zone, by
/// origin, by table) plus service metrics (table turnover, covers, ticket per
/// person). Gross comes from payments net of change, like the other reports.
@immutable
class OperationsReport {
  const OperationsReport({
    this.zones = const [],
    this.origins = const [],
    this.tables = const [],
    this.totalSales = 0,
    this.orderCount = 0,
    this.sessionCount = 0,
    this.avgTurnoverMinutes = 0,
    this.totalCovers = 0,
  });

  final List<NamedSales> zones;
  final List<NamedSales> origins;
  final List<NamedSales> tables;
  final double totalSales;
  final int orderCount;

  /// Distinct dining sessions (table occupancies) in the period.
  final int sessionCount;

  /// Average occupancy time per closed session, in minutes (0 if none).
  final double avgTurnoverMinutes;

  /// Sum of `people_count` across distinct sessions that reported it.
  final int totalCovers;

  /// Average spend per guest (gross ÷ covers); 0 when covers are unknown.
  double get ticketPerPerson => totalCovers > 0 ? totalSales / totalCovers : 0;
}

/// One sold product with its period units and revenue.
@immutable
class MenuItemStat {
  const MenuItemStat({
    required this.name,
    required this.units,
    required this.revenue,
  });
  final String name;
  final double units;
  final double revenue;
}

/// Menu report for a period: the sold products (ranked by revenue) plus the
/// active menu items that did NOT sell (dead items), so the owner can prune the
/// menu.
@immutable
class MenuEngineeringReport {
  const MenuEngineeringReport({
    this.selling = const [],
    this.deadItems = const [],
    this.menuSize = 0,
  });

  /// Sold products, sorted by revenue desc.
  final List<MenuItemStat> selling;

  /// Active menu items with zero sales in the period (sorted by name).
  final List<String> deadItems;

  /// Number of active menu items considered.
  final int menuSize;

  double get totalRevenue => selling.fold<double>(0, (s, p) => s + p.revenue);
}
