import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/auth/admin_access_profile.dart';
import '../../domain/dashboard/dashboard_models.dart';
import 'daily_sales_aggregator.dart';
import 'fiscal_aggregator.dart';
import 'menu_engineering_aggregator.dart';
import 'operations_aggregator.dart';
import 'report_load.dart';
import 'sale_scope.dart';
import 'sales_trend_aggregator.dart';
import 'tax_lines_aggregator.dart';
import 'waiter_attribution_aggregator.dart';

class DashboardDataService {
  DashboardDataService(this._client);

  final SupabaseClient _client;

  /// Executes a query with `.inFilter()` in batches to avoid URI-too-long errors.
  /// Batches queue on [ReportRequestThrottle] instead of all firing at once: a
  /// month with 3,000 orders used to be ~75 simultaneous requests.
  Future<List<Map<String, dynamic>>> _batchedInFilter({
    required String table,
    required String select,
    required String filterColumn,
    required List<String> values,
  }) =>
      fetchInBatches(
        values,
        (chunk) => _client.from(table).select(select).inFilter(filterColumn, chunk),
      );

  /// Resuelve `user_id -> nombre legible` (cajeros / meseros) vía el RPC
  /// `fn_resolve_user_names` (SECURITY DEFINER). El RPC evita la RLS de
  /// `profiles` —que solo deja leer el perfil propio— y toma el mejor dato
  /// disponible: empleados (nombre+apellido) → profiles.full_name → email.
  ///
  /// Si el RPC no está disponible (migración aún sin aplicar) degrada a una
  /// lectura directa de `profiles` y, en última instancia, a un mapa vacío,
  /// dejando que el llamador use su etiqueta genérica de respaldo.
  Future<Map<String, String>> _resolveUserNames(List<String> userIds) async {
    if (userIds.isEmpty) return const {};
    final unique = userIds.toSet().toList(growable: false);
    try {
      final rows = await ReportRequestThrottle.run(() => _client.rpc(
            'fn_resolve_user_names',
            params: {'p_user_ids': unique},
          ));
      final result = <String, String>{};
      for (final row in List<Map<String, dynamic>>.from(rows as List)) {
        final id = row['user_id']?.toString();
        if (id == null || id.isEmpty) continue;
        final name = row['display_name']?.toString().trim();
        if (name != null && name.isNotEmpty) result[id] = name;
      }
      return result;
    } on ReportLoadCancelled {
      rethrow;
    } catch (_) {
      try {
        final profileRows = await _batchedInFilter(
          table: 'profiles',
          select: 'id, full_name',
          filterColumn: 'id',
          values: unique,
        );
        final result = <String, String>{};
        for (final row in profileRows) {
          final id = row['id']?.toString();
          final name = row['full_name']?.toString().trim();
          if (id != null && name != null && name.isNotEmpty) result[id] = name;
        }
        return result;
      } on ReportLoadCancelled {
        rethrow;
      } catch (_) {
        return const {};
      }
    }
  }

  /// Loads dashboard data. Set [liteMode] to true to skip catalog, active orders,
  /// closed orders, and previous-period comparison — useful for the sales-only view.
  ///
  /// [businessDayStartHour] (0–23, default 5) define la hora local en que
  /// arranca el "día operativo" para los filtros [SalesDateFilter.today] y
  /// [SalesDateFilter.yesterday]. Permite que un turno que cruza medianoche
  /// (ej. 4 PM → 2 AM) siga contando como ventas del mismo día.
  Future<DashboardSummary> loadSummary(AdminAccessProfile profile, {
    SalesDateFilter filter = SalesDateFilter.month,
    DateTimeRange? customRange,
    bool liteMode = false,
    int businessDayStartHour = 5,
  }) async {
    final businessId = profile.businessId;
    final now = DateTime.now();

    DateTime start;
    DateTime end;
    DateTime prevStart;
    DateTime prevEnd;

    // Anchor del "día operativo" actual: día calendario con la hora de corte
    // aplicada. Si `now` está antes del corte (ej. 1 AM con corte 5 AM),
    // retrocedemos un día porque seguimos dentro del día operativo anterior.
    DateTime operationalDayAnchor(DateTime reference) {
      final candidate = DateTime(reference.year, reference.month, reference.day,
          businessDayStartHour);
      return reference.isBefore(candidate)
          ? candidate.subtract(const Duration(days: 1))
          : candidate;
    }

    switch (filter) {
      case SalesDateFilter.today:
        start = operationalDayAnchor(now);
        end = start.add(const Duration(days: 1));
        prevStart = start.subtract(const Duration(days: 1));
        prevEnd = start;
        break;
      case SalesDateFilter.yesterday:
        start = operationalDayAnchor(now).subtract(const Duration(days: 1));
        end = start.add(const Duration(days: 1));
        prevStart = start.subtract(const Duration(days: 1));
        prevEnd = start;
        break;
      case SalesDateFilter.week:
        start = DateTime(now.year, now.month, now.day).subtract(const Duration(days: 7));
        end = DateTime(now.year, now.month, now.day).add(const Duration(days: 1));
        prevStart = start.subtract(const Duration(days: 7));
        prevEnd = start;
        break;
      case SalesDateFilter.month:
        start = DateTime(now.year, now.month, 1);
        end = DateTime(now.year, now.month + 1, 1);
        prevStart = DateTime(now.year, now.month - 1, 1);
        prevEnd = start;
        break;
      case SalesDateFilter.lastMonth:
        start = DateTime(now.year, now.month - 1, 1);
        end = DateTime(now.year, now.month, 1);
        prevStart = DateTime(now.year, now.month - 2, 1);
        prevEnd = start;
        break;
      case SalesDateFilter.last3Months:
        start = DateTime(now.year, now.month - 3, 1);
        end = DateTime(now.year, now.month + 1, 1);
        prevStart = DateTime(now.year, now.month - 6, 1);
        prevEnd = start;
        break;
      case SalesDateFilter.custom:
        // El picker entrega ambas fechas a medianoche local. Con el filtro
        // [periodStart, periodEnd) un solo día (start == end) daría un rango
        // vacío y todo saldría en 0; aun en rangos de varios días el último
        // día quedaría excluido. Normalizamos al día completo y hacemos el fin
        // exclusivo al inicio del día siguiente al último día seleccionado,
        // para incluir ese día entero.
        final rawStart = customRange?.start ?? now;
        final rawEnd = customRange?.end ?? now;
        start = DateTime(rawStart.year, rawStart.month, rawStart.day);
        end = DateTime(rawEnd.year, rawEnd.month, rawEnd.day)
            .add(const Duration(days: 1));
        // Para comparación previa en custom, usamos el mismo periodo de tiempo hacia atrás
        final diff = end.difference(start);
        prevStart = start.subtract(diff);
        prevEnd = start;
        break;
    }

    final periodStart = start.toUtc().toIso8601String();
    final periodEnd = end.toUtc().toIso8601String();

    // ── Phase 1: Fire independent queries in parallel ──
    final pStart = prevStart.toUtc().toIso8601String();
    final pEnd = prevEnd.toUtc().toIso8601String();

    // The canonical "ventas" scope (sale_scope.dart): a sale is a payment
    // collected in the window, of a non-void order — even if the table is still
    // open with another check pending. Every sales figure below comes from
    // these rows, so the dashboard agrees with Ventas / Ventas por día /
    // tendencia and with the cash register.
    final periodPaymentsFuture = _salePayments(
      businessId: businessId,
      startIso: periodStart,
      endIso: periodEnd,
      select:
          'amount, change_amount, status, order_id, check_id, created_at, processed_by, payment_methods(code)',
    );

    // Previous period sales — for the growth chip.
    final prevPaymentsFuture = _salePayments(
      businessId: businessId,
      startIso: pStart,
      endIso: pEnd,
      select: 'amount, change_amount, status, created_at, order_id',
    );

    final futures = <Future<List<dynamic>>>[periodPaymentsFuture, prevPaymentsFuture];
    if (!liteMode) {
      futures.addAll([
        // Active Orders (all of them, regardless of date)
        _client.from('orders')
            .select('id, total, status_ext, created_at, closed_at, table_sessions!inner(id, business_id, customer_name, note, opened_at, people_count, origin, dining_tables(*)), order_items(product_name, qty, subtotal, tax, discounts, status, check_id, order_item_modifiers(name, qty)), payments(amount, change_amount, status), order_checks(id, position, label, is_closed, total)')
            .eq('table_sessions.business_id', businessId)
            .neq('status_ext', 'void')
            .isFilter('closed_at', null)
            .order('created_at', ascending: false).limit(1000),
        // Catalog
        _client.from('menu_items')
            .select('id, name, price, is_active, categories(name), menu_item_groups(modifier_groups(id, name, selection_mode, modifiers(id, name, price_delta, is_active)))')
            .eq('business_id', businessId).order('name', ascending: true),
        // Closed Orders for the period
        _client.from('orders')
            .select('id, total, status_ext, created_at, closed_at, table_sessions!inner(id, business_id, customer_name, note, opened_at, people_count, origin, dining_tables(*)), order_items(product_name, qty, subtotal, tax, discounts, status, check_id, order_item_modifiers(name, qty)), payments(amount, change_amount, status), order_checks(id, position, label, is_closed, total)')
            .eq('table_sessions.business_id', businessId)
            .neq('status_ext', 'void')
            .gte('closed_at', periodStart)
            .lt('closed_at', periodEnd)
            .order('closed_at', ascending: false).limit(500),
        // Cancelled orders for the period: the whole account was voided (table
        // released after sending to kitchen, order annulled, or the system
        // auto-released an empty table). Filtered by closed_at — the moment the
        // void happened — so a table opened before the period (or before the
        // 5 AM business-day cutoff) still shows up when it's cancelled today.
        // Void rows without closed_at (edge/legacy) are included too.
        _client.from('orders')
            .select('id, total, status_ext, created_at, closed_at, table_sessions!inner(id, business_id, customer_name, note, opened_at, people_count, origin, dining_tables(*)), order_items(product_name, qty, subtotal, tax, discounts, status, check_id, order_item_modifiers(name, qty)), payments(amount, change_amount, status), order_checks(id, position, label, is_closed, total)')
            .eq('table_sessions.business_id', businessId)
            .eq('status_ext', 'void')
            .or('closed_at.is.null,and(closed_at.gte.$periodStart,closed_at.lt.$periodEnd)')
            .order('created_at', ascending: false).limit(200),
      ]);
    }

    final results = await Future.wait(futures);

    final paymentRows = List<Map<String, dynamic>>.from(results[0]);
    final prevPaymentRows = List<Map<String, dynamic>>.from(results[1]);
    final activeOrdersRaw = liteMode ? const <Map<String, dynamic>>[] : List<Map<String, dynamic>>.from(results[2]);
    final productsRaw = liteMode ? const <Map<String, dynamic>>[] : List<Map<String, dynamic>>.from(results[3]);
    final closedOrdersRaw = liteMode ? const <Map<String, dynamic>>[] : List<Map<String, dynamic>>.from(results[4]);
    final cancelledOrdersRaw = liteMode ? const <Map<String, dynamic>>[] : List<Map<String, dynamic>>.from(results[5]);

    // Orders with a sale in the period (the payments are already scoped).
    final scopedOrderIds = _orderIdsOf(paymentRows);

    // ── Phase 3: Process results (CPU-only, no awaits) ──

    // Period sales & tickets
    double totalSales = 0;
    final tickets = <TicketItem>[];
    for (final row in paymentRows) {
      final oid = row['order_id']?.toString();
      final net = _netAmount(row['amount'], row['change_amount']);
      totalSales += net;
      final pm = row['payment_methods'];
      final pmCode = pm is Map<String, dynamic> ? pm['code']?.toString() : null;
      tickets.add(TicketItem(
        orderId: oid ?? '',
        amount: net,
        createdAt: DateTime.tryParse(row['created_at']?.toString() ?? '') ?? DateTime.now(),
        paymentMethodCode: pmCode,
        checkId: row['check_id']?.toString(),
      ));
    }
    tickets.sort((a, b) => b.createdAt.compareTo(a.createdAt));

    // Orders (partitioned by closed_at)
    final liveOrders = <LiveOrderItem>[];
    final closedOrders = <LiveOrderItem>[];

    // Part A: Process Live Orders.
    // Skip sessions whose origin is a one-shot sale (quick / manual). These
    // are not "mesas abiertas" — they exist briefly while the cashier rings
    // them up and shouldn't appear in the orders view, table map, or pending
    // counters.
    const nonTableOrigins = {'quick', 'manual'};
    for (final row in activeOrdersRaw) {
      if (row['closed_at'] != null) continue; // Safety check
      final session = row['table_sessions'];
      final origin = session is Map<String, dynamic>
          ? session['origin']?.toString().toLowerCase()
          : null;
      if (origin != null && nonTableOrigins.contains(origin)) continue;
      liveOrders.add(mapToLiveOrderItem(row));
    }

    // Part B: Process Closed Orders
    for (final row in closedOrdersRaw) {
      closedOrders.add(mapToLiveOrderItem(row));
    }

    // Part C: Cancelled orders of the period (table released / account voided).
    final cancelledOrders = <LiveOrderItem>[
      for (final row in cancelledOrdersRaw) mapToLiveOrderItem(row),
    ];

    // Catalog
    final catalogItems = productsRaw.map((row) {
      final groups = <CatalogModifierGroup>[];
      final rawGroups = row['menu_item_groups'] as List? ?? [];
      for (final gRow in rawGroups) {
        final mg = gRow['modifier_groups'];
        if (mg is! Map<String, dynamic>) continue;
        final mods = (mg['modifiers'] as List? ?? [])
            .whereType<Map<String, dynamic>>()
            .map((m) => CatalogModifier(
                  name: m['name']?.toString() ?? '',
                  priceDelta: _toDoubleOrNull(m['price_delta']) ?? 0,
                  isActive: m['is_active'] == true,
                ))
            .toList(growable: false);
        groups.add(CatalogModifierGroup(
          name: mg['name']?.toString() ?? '',
          selectionMode: mg['selection_mode']?.toString() ?? 'modifier',
          modifiers: mods,
        ));
      }
      return CatalogItem(
        name: row['name']?.toString() ?? 'Sin nombre',
        status: (row['is_active'] == true) ? 'Activo' : 'Inactivo',
        price: _toDoubleOrNull(row['price']),
        category: row['categories'] is Map<String, dynamic>
            ? row['categories']['name']?.toString()
            : null,
        modifierGroups: groups,
      );
    }).toList(growable: false);

    // ── Phase 4: Top products & Category aggregation: lines sold in the period ──
    final topProductsRaw = await _soldItems(
      businessId: businessId,
      start: start,
      end: end,
      paidOrderIds: scopedOrderIds,
      select: 'order_id, product_name, quantity, qty, total, menu_items(categories(name))',
    );

    final Map<String, TopProduct> aggregate = {};
    final Map<String, double> categoryAggregate = {};

    for (final row in topProductsRaw) {
      if (row['status']?.toString() == 'void') continue;
      final label = row['product_name']?.toString().trim().isNotEmpty == true
          ? row['product_name'].toString().trim()
          : 'Producto';
      
      final amount = _toDouble(row['total']);
      final qty = _toDouble(row['qty'] ?? row['quantity']);

      // Top products
      final currentProd = aggregate[label];
      aggregate[label] = TopProduct(
        label: label, 
        amount: (currentProd?.amount ?? 0) + amount, 
        quantity: (currentProd?.quantity ?? 0) + qty,
      );

      // Categories
      final mi = row['menu_items'];
      final catRaw = mi is Map<String, dynamic> && mi['categories'] is Map<String, dynamic>
          ? mi['categories']['name']?.toString()
          : 'Otros';
      final cat = catRaw ?? 'Otros';
      categoryAggregate[cat] = (categoryAggregate[cat] ?? 0) + amount;
    }

    final topProducts = aggregate.values.toList()
      ..sort((a, b) => b.amount.compareTo(a.amount));
    
    final List<SalesByCategory> salesByCategory = categoryAggregate.entries
        .map<SalesByCategory>((e) => SalesByCategory(label: e.key, amount: e.value))
        .toList()
      ..sort((a, b) => b.amount.compareTo(a.amount));

    // Hourly sales + method breakdown (period-scoped)
    final Map<int, double> hourlyMap = {};
    final Map<String, double> methodTotals = {};
    for (final row in paymentRows) {
      final net = _netAmount(row['amount'], row['change_amount']);
      final createdAt = DateTime.tryParse(row['created_at']?.toString() ?? '');
      if (createdAt != null) {
        final hour = createdAt.toLocal().hour;
        hourlyMap[hour] = (hourlyMap[hour] ?? 0) + net;
      }
      final pm = row['payment_methods'];
      final code = pm is Map<String, dynamic> ? pm['code']?.toString() ?? 'other' : 'other';
      methodTotals[code] = (methodTotals[code] ?? 0) + net;
    }
    final hourlySales = hourlyMap.entries
        .map((e) => HourlySale(hour: e.key, amount: e.value)).toList()
      ..sort((a, b) => a.hour.compareTo(b.hour));
    final salesByMethod = methodTotals.entries
        .map((e) => SalesByMethod(code: e.key, amount: e.value)).toList()
      ..sort((a, b) => b.amount.compareTo(a.amount));

    // Previous period comparison — same canonical scope so the growth chip
    // compares like with like.
    double previousDaySales = 0;
    for (final row in prevPaymentRows) {
      previousDaySales += _netAmount(row['amount'], row['change_amount']);
    }

    // Pending
    double pendingAmount = 0;
    final pendingTables = <PendingTable>[];
    for (final order in liveOrders) {
      pendingAmount += order.total;
      pendingTables.add(PendingTable(
        tableName: order.title,
        customerName: order.subtitle,
        total: order.total,
        status: order.status,
        itemCount: order.items.length,
      ));
    }

    // Top seller (disabled — order_items lacks created_by column)
    TopSeller? topSeller;

    // ── Waiter/cashier performance: aggregate per person, restricted to the
    // canonical scope (paid orders) so their totals reconcile with totalSales.
    final paymentOrderIds = scopedOrderIds.toList(growable: false);

    final performanceResults = await Future.wait([
      _loadWaiterPerformance(
        paymentRows: paymentRows,
        paymentOrderIds: paymentOrderIds,
      ),
      _loadCashierPerformance(
        paymentRows: paymentRows,
        scopedOrderIds: scopedOrderIds,
      ),
    ]);
    final waiterPerformance = performanceResults[0] as List<WaiterPerformance>;
    final cashierPerformance = performanceResults[1] as List<CashierPerformance>;

    final activeOrdersCount = liveOrders.length;
    // Órdenes = distinct paid orders, NOT payments. A table split into N checks
    // settles with N payments but is ONE order, so counting payments inflated
    // "Órdenes" and deflated "Ticket Promedio". Count distinct order_ids instead.
    final totalTickets = tickets
        .map((t) => t.orderId)
        .where((id) => id.isNotEmpty)
        .toSet()
        .length;

    return DashboardSummary(
      profile: profile,
      totalSales: totalSales,
      totalTickets: totalTickets,
      averageTicket: totalTickets == 0 ? 0 : totalSales / totalTickets,
      activeOrders: activeOrdersCount,
      topProducts: topProducts,
      catalogItems: catalogItems,
      liveOrders: liveOrders,
      closedOrders: closedOrders,
      cancelledOrders: cancelledOrders,
      hourlySales: hourlySales,
      salesByMethod: salesByMethod,
      salesByCategory: salesByCategory,
      topSeller: topSeller,
      filter: filter,
      customRange: customRange,
      pendingAmount: pendingAmount,
      previousDaySales: previousDaySales,
      tickets: tickets,
      pendingTables: pendingTables,
      waiterPerformance: waiterPerformance,
      cashierPerformance: cashierPerformance,
      periodStart: start,
      periodEnd: end,
    );
  }

  /// Aggregates the period's payments per cashier (`payments.processed_by`)
  /// and resolves their display names. Restricted to the canonical scope (paid
  /// orders) and to payments with an assigned cashier.
  Future<List<CashierPerformance>> _loadCashierPerformance({
    required List<Map<String, dynamic>> paymentRows,
    required Set<String> scopedOrderIds,
  }) async {
    final agg = <String, _CashierAgg>{};
    for (final row in paymentRows) {
      final orderId = row['order_id']?.toString();
      if (orderId == null || !scopedOrderIds.contains(orderId)) continue;
      final processedBy = row['processed_by']?.toString();
      if (processedBy == null || processedBy.isEmpty) continue;
      final net = _netAmount(row['amount'], row['change_amount']);
      final entry = agg.putIfAbsent(processedBy, _CashierAgg.new);
      entry.total += net;
      entry.ticketCount += 1;
      entry.orderIds.add(orderId);
    }
    if (agg.isEmpty) return const [];

    final cashierIds = agg.keys.toList(growable: false);
    final namesById = await _resolveUserNames(cashierIds);

    final result = agg.entries
        .map((e) => CashierPerformance(
              userId: e.key,
              name: namesById[e.key] ?? 'Cajero',
              totalSales: e.value.total,
              ticketCount: e.value.ticketCount,
              tablesCount: e.value.orderIds.length,
            ))
        .toList()
      ..sort((a, b) => b.totalSales.compareTo(a.totalSales));
    return result;
  }

  /// Aggregates the period's payments per waiter (`table_sessions.waiter_user_id`)
  /// and resolves their display names from the `profiles` table. Excludes
  /// payments tied to sessions without an assigned waiter.
  Future<List<WaiterPerformance>> _loadWaiterPerformance({
    required List<Map<String, dynamic>> paymentRows,
    required List<String> paymentOrderIds,
  }) async {
    if (paymentOrderIds.isEmpty) return const [];

    // 1. Map orderId → (waiterUserId, sessionId).
    final orderRows = await _batchedInFilter(
      table: 'orders',
      select: 'id, table_sessions!inner(id, waiter_user_id)',
      filterColumn: 'id',
      values: paymentOrderIds,
    );
    final orderToWaiter = <String, String>{};
    final orderToSession = <String, String>{};
    for (final row in orderRows) {
      final oid = row['id']?.toString();
      if (oid == null || oid.isEmpty) continue;
      final session = row['table_sessions'];
      if (session is Map<String, dynamic>) {
        final wid = session['waiter_user_id']?.toString();
        final sid = session['id']?.toString();
        if (wid != null && wid.isNotEmpty) orderToWaiter[oid] = wid;
        if (sid != null && sid.isNotEmpty) orderToSession[oid] = sid;
      }
    }
    if (orderToWaiter.isEmpty) return const [];

    // 2. Aggregate payments per waiter.
    final agg = <String, _WaiterAgg>{};
    for (final row in paymentRows) {
      final oid = row['order_id']?.toString();
      if (oid == null) continue;
      final waiterId = orderToWaiter[oid];
      if (waiterId == null) continue;
      final status = row['status']?.toString();
      if (status == 'void' || status == 'cancelled') continue;
      final net = _netAmount(row['amount'], row['change_amount']);
      final entry = agg.putIfAbsent(waiterId, _WaiterAgg.new);
      entry.total += net;
      entry.ticketCount += 1;
      final sessionId = orderToSession[oid];
      if (sessionId != null) entry.sessions.add(sessionId);
    }
    if (agg.isEmpty) return const [];

    // 3. Resolve waiter names.
    final waiterIds = agg.keys.toList(growable: false);
    final namesById = await _resolveUserNames(waiterIds);

    final result = agg.entries
        .map((e) => WaiterPerformance(
              userId: e.key,
              name: namesById[e.key] ?? 'Mesero',
              totalSales: e.value.total,
              ticketCount: e.value.ticketCount,
              tablesCount: e.value.sessions.length,
            ))
        .toList()
      ..sort((a, b) => b.totalSales.compareTo(a.totalSales));
    return result;
  }

  @visibleForTesting
  LiveOrderItem mapToLiveOrderItem(Map<String, dynamic> row) {
    final session = row['table_sessions'];
    final tableData = session is Map<String, dynamic> ? session['dining_tables'] : null;
    final tableLabel = tableData is Map<String, dynamic>
        ? (tableData['label']?.toString() ?? tableData['code']?.toString() ?? 'Mesa')
        : 'Orden';
    final tableId = tableData is Map<String, dynamic> ? tableData['id']?.toString() : null;
    final customerName = session is Map<String, dynamic>
        ? session['customer_name']?.toString()
        : null;
    final sessionNote = session is Map<String, dynamic>
        ? session['note']?.toString()
        : null;
    final openedAt = session is Map<String, dynamic>
        ? DateTime.tryParse(session['opened_at']?.toString() ?? '')
        : null;
    final peopleCount = session is Map<String, dynamic>
        ? (session['people_count'] is int
            ? session['people_count'] as int
            : int.tryParse(session['people_count']?.toString() ?? ''))
        : null;

    // Checks already settled (is_closed) — their items are out of the open bill.
    final closedCheckIds = <String>{};
    final rawChecks = row['order_checks'];
    if (rawChecks is List) {
      for (final c in rawChecks) {
        if (c is Map && c['is_closed'] == true) {
          final id = c['id']?.toString();
          if (id != null && id.isNotEmpty) closedCheckIds.add(id);
        }
      }
    }

    // Per the POS (order_pricing_utils.summarizeOrderPricing): recompute each
    // line from subtotal + tax − discounts. NEVER use order_items.total — it's a
    // pre-tax generated column (quantity*unit_price, no tax/mods/discounts).
    // Void items go to a separate list (never into the balance) so the UI can
    // surface what was removed from the bill. An ACTIVE order lists only its
    // OPEN items (unpaid and not in a closed check) → the remaining balance,
    // exactly like the POS table screen; a CLOSED order lists everything it sold.
    // The header total is ALWAYS the sum of the displayed items, so the list and
    // the total can never disagree.
    final isClosed = row['closed_at'] != null;
    final isVoidOrder = row['status_ext']?.toString() == 'void';
    final rawItems = row['order_items'] as List? ?? [];
    final childItems = <LiveChildItem>[];
    final voidedItems = <LiveChildItem>[];
    final checkItemCounts = <String, int>{};
    var itemsTotal = 0.0;
    for (final ri in rawItems) {
      if (ri is! Map) continue;
      final status = ri['status']?.toString();
      final amount = _toDouble(ri['subtotal']) +
          _toDouble(ri['tax']) -
          _toDouble(ri['discounts']);
      final modifiers = ri['order_item_modifiers'] as List? ?? [];
      final extras =
          modifiers.map((m) => m['name']?.toString()).whereType<String>().toList();
      if (status == 'void') {
        voidedItems.add(LiveChildItem(
          name: ri['product_name']?.toString() ?? 'Producto',
          quantity: _toDouble(ri['qty'] ?? ri['quantity']),
          total: amount,
          extras: extras,
          isVoid: true,
        ));
        continue;
      }
      final checkId = ri['check_id']?.toString();
      if (checkId != null && checkId.isNotEmpty) {
        checkItemCounts[checkId] = (checkItemCounts[checkId] ?? 0) + 1;
      }
      final settled = status == 'paid' ||
          (ri['check_id'] != null &&
              closedCheckIds.contains(ri['check_id'].toString()));
      if (!isClosed && !isVoidOrder && settled) {
        continue; // active → only the open remainder
      }
      itemsTotal += amount;
      childItems.add(LiveChildItem(
        name: ri['product_name']?.toString() ?? 'Producto',
        quantity: _toDouble(ri['qty'] ?? ri['quantity']),
        total: amount,
        extras: extras,
      ));
    }

    final zone = tableData is Map<String, dynamic>
        ? (tableData['zone_name']?.toString() ??
            tableData['zone']?.toString() ??
            tableData['area_name']?.toString() ??
            tableData['area']?.toString())
        : null;

    // Net of completed payments — fallback for closed orders with no live items.
    var paid = 0.0;
    final payments = row['payments'];
    if (payments is List) {
      for (final p in payments) {
        if (p is! Map) continue;
        final status = p['status']?.toString();
        if (status == 'void' || status == 'cancelled') continue;
        paid += _toDouble(p['amount']) - _toDouble(p['change_amount']);
      }
    }

    // A voided order's headline is the amount that was cancelled (its lines
    // typically all end up void, so the open balance would read RD$0).
    // An ACTIVE order's total is only what's left to collect: with everything
    // paid it's RD$0, never the money already collected (that inflated
    // «Por Cobrar» with paid orders the POS left open).
    final voidedTotal =
        voidedItems.fold(0.0, (sum, i) => sum + i.total);
    final total = isVoidOrder
        ? (itemsTotal + voidedTotal > 0
            ? itemsTotal + voidedTotal
            : _toDouble(row['total']))
        : !isClosed
            ? itemsTotal
            : itemsTotal > 0
                ? itemsTotal
                : (paid > 0 ? paid : _toDouble(row['total']));

    // Per-check breakdown, only for genuinely divided accounts (2+ checks).
    // Each check shows its amount (order_checks.total) + paid state (is_closed),
    // just like the POS split view (C1/C2… with pagada/pendiente).
    final checks = <OrderCheckSummary>[];
    if (rawChecks is List && rawChecks.length >= 2) {
      final sorted = rawChecks.whereType<Map>().toList()
        ..sort((a, b) =>
            _toDouble(a['position']).compareTo(_toDouble(b['position'])));
      for (final c in sorted) {
        final checkTotal = _toDouble(c['total']);
        final id = c['id']?.toString();
        final count = id != null ? (checkItemCounts[id] ?? 0) : 0;
        if (checkTotal <= 0.009 && count == 0) continue; // empty pool → skip
        final pos = _toDouble(c['position']).toInt();
        final label = (c['label']?.toString().trim().isNotEmpty ?? false)
            ? c['label'].toString().trim()
            : 'C$pos';
        checks.add(OrderCheckSummary(
          label: label,
          total: checkTotal,
          isPaid: c['is_closed'] == true,
          itemCount: count,
        ));
      }
    }

    return LiveOrderItem(
      id: row['id']?.toString() ?? '',
      title: tableLabel,
      subtitle: customerName ?? row['status_ext']?.toString() ?? 'open',
      total: total,
      status: row['status_ext']?.toString() ?? 'open',
      items: childItems,
      voidedItems: voidedItems,
      checks: checks,
      zone: zone,
      tableId: tableId,
      openedAt: openedAt,
      peopleCount: peopleCount,
      sessionNote: sessionNote,
    );
  }

  /// Loads customer analytics for the period — aggregates fiscal documents by
  /// RNC (preferred) or normalized customer name. Customers without RNC AND
  /// without name are excluded (treated as anonymous walk-ins).
  Future<List<CustomerSummary>> loadCustomerAnalytics({
    required String businessId,
    required DateTime start,
    required DateTime end,
  }) async {
    final rows = await ReportRequestThrottle.run(() => _client
        .from('fiscal_documents')
        .select('order_id, total, status, created_at, customer_rnc, customer_name')
        .eq('business_id', businessId)
        .gte('created_at', start.toUtc().toIso8601String())
        .lt('created_at', end.toUtc().toIso8601String())
        .eq('status', 'active'));

    final agg = <String, _CustomerAgg>{};
    for (final row in List<Map<String, dynamic>>.from(rows)) {
      final rnc = row['customer_rnc']?.toString().trim();
      final name = row['customer_name']?.toString().trim();
      final hasRnc = rnc != null && rnc.isNotEmpty;
      final hasName = name != null && name.isNotEmpty;
      if (!hasRnc && !hasName) continue; // anonymous — skip

      final key = hasRnc ? 'rnc:$rnc' : 'name:${name!.toLowerCase()}';
      final entry = agg.putIfAbsent(key, _CustomerAgg.new);
      final amount = _toDouble(row['total']);
      final createdAt =
          DateTime.tryParse(row['created_at']?.toString() ?? '') ?? DateTime.now();
      final orderId = row['order_id']?.toString();

      entry.totalSpent += amount;
      if (orderId != null && orderId.isNotEmpty) {
        entry.orderIds.add(orderId);
      } else {
        // No order_id (rare) — still count as a visit.
        entry.bareVisits += 1;
      }
      entry.firstVisit = entry.firstVisit == null || createdAt.isBefore(entry.firstVisit!)
          ? createdAt
          : entry.firstVisit;
      entry.lastVisit = entry.lastVisit == null || createdAt.isAfter(entry.lastVisit!)
          ? createdAt
          : entry.lastVisit;
      // Keep the prettiest name we've seen (longest non-empty).
      if (hasName && (entry.displayName == null || name.length > entry.displayName!.length)) {
        entry.displayName = name;
      }
      if (hasRnc) entry.rnc = rnc;
    }

    return agg.entries
        .map((e) {
          final visits = e.value.orderIds.length + e.value.bareVisits;
          return CustomerSummary(
            customerKey: e.key,
            displayName: e.value.displayName ?? e.value.rnc ?? 'Cliente',
            rnc: e.value.rnc,
            totalSpent: e.value.totalSpent,
            visitCount: visits,
            firstVisit: e.value.firstVisit ?? DateTime.now(),
            lastVisit: e.value.lastVisit ?? DateTime.now(),
          );
        })
        .toList()
      ..sort((a, b) => b.totalSpent.compareTo(a.totalSpent));
  }

  /// Loads all visits (payments) made by a single customer in the period.
  /// Used by the customer drill-down view. Caller passes the same key/rnc
  /// returned by [loadCustomerAnalytics].
  Future<List<CustomerVisit>> loadCustomerVisits({
    required String businessId,
    required String customerKey,
    required DateTime start,
    required DateTime end,
  }) async {
    final isRnc = customerKey.startsWith('rnc:');
    final value = customerKey.substring(customerKey.indexOf(':') + 1);

    var query = _client
        .from('fiscal_documents')
        .select(
            'id, order_id, total, status, created_at, customer_rnc, customer_name, payments(payment_methods(code)), orders(table_sessions(dining_tables(label, code)))')
        .eq('business_id', businessId)
        .gte('created_at', start.toUtc().toIso8601String())
        .lt('created_at', end.toUtc().toIso8601String())
        .eq('status', 'active');

    if (isRnc) {
      query = query.eq('customer_rnc', value);
    } else {
      query = query.ilike('customer_name', value);
    }

    final rows = await query.order('created_at', ascending: false);

    return List<Map<String, dynamic>>.from(rows).map((row) {
      final payment = row['payments'];
      final pm = payment is Map<String, dynamic> ? payment['payment_methods'] : null;
      final order = row['orders'];
      final session = order is Map<String, dynamic> ? order['table_sessions'] : null;
      final table = session is Map<String, dynamic> ? session['dining_tables'] : null;
      return CustomerVisit(
        orderId: row['order_id']?.toString() ?? '',
        amount: _toDouble(row['total']),
        createdAt: DateTime.tryParse(row['created_at']?.toString() ?? '') ?? DateTime.now(),
        tableLabel: table is Map<String, dynamic>
            ? (table['label']?.toString() ?? table['code']?.toString())
            : null,
        paymentMethodCode: pm is Map<String, dynamic> ? pm['code']?.toString() : null,
      );
    }).toList(growable: false);
  }

  /// Loads modifiers (extras / options like "Extra queso") aggregated for the
  /// period. Sourced from `order_item_modifiers` joined via order_items →
  /// orders → table_sessions for the business + period filter.
  Future<List<ModifierSummary>> loadModifiersBreakdown({
    required String businessId,
    required DateTime start,
    required DateTime end,
  }) async {
    final rows = await ReportRequestThrottle.run(() => _client
        .from('order_item_modifiers')
        .select(
            'name, qty, price, order_items!inner(status, orders!inner(created_at, table_sessions!inner(business_id)))')
        .eq('order_items.orders.table_sessions.business_id', businessId)
        .gte('order_items.orders.created_at', start.toUtc().toIso8601String())
        .lt('order_items.orders.created_at', end.toUtc().toIso8601String())
        .neq('order_items.status', 'void'));

    final agg = <String, _ModifierAgg>{};
    for (final row in List<Map<String, dynamic>>.from(rows)) {
      final name = row['name']?.toString().trim();
      if (name == null || name.isEmpty) continue;
      final qty = _toDouble(row['qty']);
      final unitQty = qty == 0 ? 1.0 : qty;
      final unitPrice = _toDouble(row['price']);
      final entry = agg.putIfAbsent(name, _ModifierAgg.new);
      entry.count += unitQty;
      entry.revenue += unitPrice * unitQty;
    }

    final result = agg.entries
        .map((e) => ModifierSummary(
              name: e.key,
              count: e.value.count,
              revenue: e.value.revenue,
            ))
        .toList()
      ..sort((a, b) {
        // Sort by revenue desc; if both are zero, fall back to count desc.
        final byRev = b.revenue.compareTo(a.revenue);
        if (byRev != 0) return byRev;
        return b.count.compareTo(a.count);
      });
    return result;
  }

  /// "Ventas por día": the gross sales of each day in [start, end) plus the
  /// range's tax breakdown.
  ///
  /// Gross per day = the sale payments collected that day, net of change
  /// ([_salePayments]) — `orders.total` is not maintained in this backend. Taxes come from `order_item_tax_lines`
  /// grouped by `tax_name`, so every configured tax/charge appears by its real
  /// name (nothing hardcoded). `netTotal = grossTotal − Σ taxes`.
  Future<DailySalesReport> loadDailySales({
    required String businessId,
    required DateTime start,
    required DateTime end,
    int cutoffHour = 0,
  }) async {
    final startIso = start.toUtc().toIso8601String();
    final endIso = end.toUtc().toIso8601String();

    // The money (sale payments) and the taxes of the lines sold in the range
    // (sale_scope.dart), so taxes never disagree with ventas.
    final payRows = await _salePayments(
      businessId: businessId,
      startIso: startIso,
      endIso: endIso,
      select: 'amount, change_amount, order_id, created_at',
    );
    final taxRows = await _soldTaxRows(
      businessId: businessId,
      start: start,
      end: end,
      paidOrderIds: _orderIdsOf(payRows),
    );

    // Money math lives in a pure, unit-tested aggregator.
    return aggregateDailySales(
      payRows: payRows,
      cutoffHour: cutoffHour,
      taxRows: taxRows,
    );
  }

  /// Tax lines of the lines sold in [start, end) (sale_scope.dart): of the
  /// orders with a sale in the range or closed in it, the lines sold inside.
  /// If the range has no `order_item_tax_lines` at all, derives equivalent rows
  /// from `order_items.tax` + the `taxes` config (mirror of the POS tax
  /// report). Without that, businesses/ranges older than the trigger that
  /// fills the tax lines showed "Impuestos 0" although tax was charged.
  Future<List<Map<String, dynamic>>> _soldTaxRows({
    required String businessId,
    required DateTime start,
    required DateTime end,
    required Set<String> paidOrderIds,
  }) async {
    final orderIds = await _saleScopeOrderIds(
      businessId: businessId,
      start: start,
      end: end,
      paidOrderIds: paidOrderIds,
    );
    if (orderIds.isEmpty) return const [];
    final rows = await _pagedInBatches(
      orderIds,
      (chunk, from, to) => _client
          .from('order_item_tax_lines')
          .select(
              'tax_name, tax_rate, amount, order_items!inner(order_id, status, order_checks(is_closed, closed_at), orders!inner(status_ext, closed_at))')
          .eq('business_id', businessId)
          .inFilter('order_items.order_id', chunk)
          .range(from, to),
    );
    final sold = [
      for (final row in rows)
        if (row['order_items'] is Map<String, dynamic> &&
            itemSoldInRange(row['order_items'] as Map<String, dynamic>, start, end))
          row,
    ];
    if (rows.isNotEmpty) return sold;

    final itemRows = await _soldItems(
      businessId: businessId,
      start: start,
      end: end,
      paidOrderIds: paidOrderIds,
      select: 'tax, tax_rate',
    );
    if (itemRows.isEmpty) return const [];
    final taxConfigs = List<Map<String, dynamic>>.from(
      await ReportRequestThrottle.run(() => _client
          .from('taxes')
          .select('name, rate, is_active')
          .eq('business_id', businessId)),
    );
    return deriveTaxRowsFromItems(itemRows: itemRows, taxConfigs: taxConfigs);
  }

  /// Sales trend over [start, end): gross per week/month bucket plus a
  /// weekday×hour heatmap. Same money source as [loadDailySales] (payments net
  /// of change), bucketed by the pure [aggregateSalesTrend].
  Future<SalesTrendReport> loadSalesTrend({
    required String businessId,
    required DateTime start,
    required DateTime end,
    required TrendGranularity granularity,
  }) async {
    final startIso = start.toUtc().toIso8601String();
    final endIso = end.toUtc().toIso8601String();

    final payRows = await _salePayments(
      businessId: businessId,
      startIso: startIso,
      endIso: endIso,
      select: 'amount, change_amount, order_id, created_at',
    );

    return aggregateSalesTrend(
      payRows: payRows,
      rangeStart: start,
      rangeEnd: end,
      granularity: granularity,
    );
  }

  /// Operations report for [start, end): gross by zone/origin/table plus table
  /// turnover, covers and ticket-per-person. Revenue from payments net of
  /// change, attributed through each paid order's dining session.
  Future<OperationsReport> loadOperations({
    required String businessId,
    required DateTime start,
    required DateTime end,
  }) async {
    final startIso = start.toUtc().toIso8601String();
    final endIso = end.toUtc().toIso8601String();

    // Sale payments, then the session facts of the orders they belong to.
    final payRows = await _salePayments(
      businessId: businessId,
      startIso: startIso,
      endIso: endIso,
      select: 'amount, change_amount, order_id',
    );
    final orderRows = await _batchedInFilter(
      table: 'orders',
      select:
          'id, table_sessions!inner(id, opened_at, closed_at, people_count, origin, dining_tables(label, code, zones(name)))',
      filterColumn: 'id',
      values: _orderIdsOf(payRows).toList(),
    );

    return aggregateOperations(orderRows: orderRows, payRows: payRows);
  }

  /// Menu-engineering report for [start, end): classifies what sells and lists
  /// the active menu items that did not sell. Reuses [loadTopProductsForPeriod]
  /// for the sold side and diffs it against the active menu catalog.
  Future<MenuEngineeringReport> loadMenuEngineering({
    required String businessId,
    required DateTime start,
    required DateTime end,
  }) async {
    // Kick off both concurrently, await separately (heterogeneous result types).
    final menuFuture = ReportRequestThrottle.run(() => _client
        .from('menu_items')
        .select('name, is_active')
        .eq('business_id', businessId)
        .eq('is_active', true));
    final soldFuture =
        loadTopProductsForPeriod(businessId: businessId, start: start, end: end);

    final menuRows = List<Map<String, dynamic>>.from(await menuFuture);
    final menuNames = menuRows
        .map((r) => r['name']?.toString() ?? '')
        .where((n) => n.trim().isNotEmpty)
        .toList();

    final sold = (await soldFuture)
        .map((p) => (name: p.label, units: p.quantity, revenue: p.amount))
        .toList();

    return aggregateMenuEngineering(menuNames: menuNames, sold: sold);
  }

  /// Fiscal report for [start, end): NCF by type, e-CF DGII status and the
  /// consolidated ITBIS/total. Sourced from `fiscal_documents` by issue date.
  Future<FiscalReport> loadFiscal({
    required String businessId,
    required DateTime start,
    required DateTime end,
  }) async {
    final startIso = start.toUtc().toIso8601String();
    final endIso = end.toUtc().toIso8601String();

    final results = await Future.wait([
      _paginate((from, to) => _client
          .from('fiscal_documents')
          .select('ncf_type, ncf_number, subtotal, itbis_amount, total, status')
          .eq('business_id', businessId)
          .gte('issued_at', startIso)
          .lt('issued_at', endIso)
          .order('issued_at', ascending: true)
          .range(from, to)),
      // Taxes of the lines sold in the range (same scope as ventas).
      _salePayments(
        businessId: businessId,
        startIso: startIso,
        endIso: endIso,
        select: 'order_id',
      ),
    ]);

    return aggregateFiscal(
      fiscalRows: results[0],
      taxRows: await _soldTaxRows(
        businessId: businessId,
        start: start,
        end: end,
        paidOrderIds: _orderIdsOf(results[1]),
      ),
    );
  }

  /// Fetches every page of a PostgREST query (which caps responses at ~1000
  /// rows) by walking `.range()` until a short page is returned. Pages go
  /// through [ReportRequestThrottle] and stop early if the report load that
  /// asked for them was cancelled.
  Future<List<Map<String, dynamic>>> _paginate(
    Future<dynamic> Function(int from, int to) page,
  ) =>
      fetchAllPages(page);

  /// The canonical "ventas" scope (sale_scope.dart): payments collected in
  /// [startIso, endIso), not void/cancelled, of a non-void order. A table that
  /// pays one check and leaves another pending counts what it paid, when it
  /// paid it — like the cash register and the POS receipts. Every sales figure
  /// in the app (Inicio, Ventas, Ventas por día, tendencia, operaciones) sums
  /// these rows, so no two reports disagree. Payments without an order
  /// (abonos) are not sales. [select] are `payments` columns.
  Future<List<Map<String, dynamic>>> _salePayments({
    required String businessId,
    required String startIso,
    required String endIso,
    required String select,
  }) =>
      _paginate((from, to) => _client
          .from('payments')
          .select('$select, orders!inner(status_ext)')
          .eq('business_id', businessId)
          .gte('created_at', startIso)
          .lt('created_at', endIso)
          .not('status', 'in', '(void,cancelled)')
          .neq('orders.status_ext', 'void')
          .range(from, to));

  static Set<String> _orderIdsOf(List<Map<String, dynamic>> rows) => {
        for (final row in rows)
          if (row['order_id']?.toString().isNotEmpty == true)
            row['order_id'].toString(),
      };

  /// Orders whose lines may have been sold in [start, end): those with a sale
  /// payment in the range ([paidOrderIds]) plus those closed in it (a line
  /// without a paid check is sold when its order closes).
  Future<List<String>> _saleScopeOrderIds({
    required String businessId,
    required DateTime start,
    required DateTime end,
    required Set<String> paidOrderIds,
  }) async {
    final closed = await _paginate((from, to) => _client
        .from('orders')
        .select('id')
        .eq('business_id', businessId)
        .neq('status_ext', 'void')
        .gte('closed_at', start.toUtc().toIso8601String())
        .lt('closed_at', end.toUtc().toIso8601String())
        .range(from, to));
    return {...paidOrderIds, ..._idsOf(closed)}.toList(growable: false);
  }

  static Set<String> _idsOf(List<Map<String, dynamic>> rows) => {
        for (final row in rows)
          if (row['id']?.toString().isNotEmpty == true) row['id'].toString(),
      };

  /// `order_items` sold in [start, end) (sale_scope.dart): each line counts
  /// once, when its check was paid or, without a paid check, when its order
  /// closed. [select] are `order_items` columns (status, check and order are
  /// added).
  Future<List<Map<String, dynamic>>> _soldItems({
    required String businessId,
    required DateTime start,
    required DateTime end,
    required Set<String> paidOrderIds,
    required String select,
  }) async {
    final orderIds = await _saleScopeOrderIds(
      businessId: businessId,
      start: start,
      end: end,
      paidOrderIds: paidOrderIds,
    );
    if (orderIds.isEmpty) return const [];
    final rows = await _pagedInBatches(
      orderIds,
      (chunk, from, to) => _client
          .from('order_items')
          .select(
              '$select, status, order_checks(is_closed, closed_at), orders!inner(status_ext, closed_at)')
          .inFilter('order_id', chunk)
          .range(from, to),
    );
    return [
      for (final row in rows)
        if (itemSoldInRange(row, start, end)) row,
    ];
  }

  /// [_batchedInFilter] that also walks every page of each batch, so a batch
  /// of big tables never gets cut at PostgREST's ~1000-row cap.
  Future<List<Map<String, dynamic>>> _pagedInBatches(
    List<String> ids,
    dynamic Function(List<String> chunk, int from, int to) page, {
    int batchSize = 40,
  }) async {
    final batches = await Future.wait([
      for (var i = 0; i < ids.length; i += batchSize)
        _paginate((from, to) async => page(
              ids.sublist(i, i + batchSize > ids.length ? ids.length : i + batchSize),
              from,
              to,
            )),
    ]);
    return [for (final batch in batches) ...batch];
  }

  /// Loads tickets (sale payments) for an arbitrary period, with the canonical
  /// scope ([_salePayments]). So the "Ventas" screen totals match "Ventas por
  /// día" and the dashboard for the same range.
  Future<({double totalSales, List<TicketItem> tickets})> loadTicketsForPeriod({
    required String businessId,
    required DateTime start,
    required DateTime end,
  }) async {
    final payRows = await _salePayments(
      businessId: businessId,
      startIso: start.toUtc().toIso8601String(),
      endIso: end.toUtc().toIso8601String(),
      select: 'amount, change_amount, status, order_id, check_id, created_at, payment_methods(code)',
    );

    double totalSales = 0;
    final tickets = <TicketItem>[];
    for (final row in payRows) {
      final oid = row['order_id']?.toString();
      if (oid == null) continue;
      final net = _netAmount(row['amount'], row['change_amount']);
      totalSales += net;
      final pm = row['payment_methods'];
      final pmCode = pm is Map<String, dynamic> ? pm['code']?.toString() : null;
      tickets.add(TicketItem(
        orderId: oid,
        amount: net,
        createdAt: DateTime.tryParse(row['created_at']?.toString() ?? '') ?? DateTime.now(),
        paymentMethodCode: pmCode,
        checkId: row['check_id']?.toString(),
      ));
    }
    tickets.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return (totalSales: totalSales, tickets: tickets);
  }

  /// Top products for an arbitrary period: the lines sold in the range
  /// ([_soldItems]), so the product totals reconcile with every other sales
  /// figure.
  Future<List<TopProduct>> loadTopProductsForPeriod({
    required String businessId,
    required DateTime start,
    required DateTime end,
  }) async {
    final payRows = await _salePayments(
      businessId: businessId,
      startIso: start.toUtc().toIso8601String(),
      endIso: end.toUtc().toIso8601String(),
      select: 'order_id',
    );
    final itemRows = await _soldItems(
      businessId: businessId,
      start: start,
      end: end,
      paidOrderIds: _orderIdsOf(payRows),
      select: 'order_id, product_name, quantity, qty, total',
    );

    final Map<String, TopProduct> agg = {};
    for (final row in itemRows) {
      final label = row['product_name']?.toString().trim().isNotEmpty == true
          ? row['product_name'].toString().trim()
          : 'Producto';
      final amount = _toDouble(row['total']);
      final qty = _toDouble(row['qty'] ?? row['quantity']);
      final current = agg[label];
      agg[label] = TopProduct(
        label: label,
        amount: (current?.amount ?? 0) + amount,
        quantity: (current?.quantity ?? 0) + qty,
      );
    }

    final result = agg.values.toList()
      ..sort((a, b) => b.amount.compareTo(a.amount));
    return result;
  }

  /// Loads the items (productos) of a single order. Used by the comandas
  /// timeline view to lazy-expand each ticket without bloating the period
  /// query.
  /// Items of an order for the comanda expansion. When [checkId] is given (a
  /// check-level payment), only that check's items are returned — so a split-paid
  /// order doesn't repeat the whole item list under every payment tile. Line
  /// amount is subtotal+tax−discounts (never order_items.total, a pre-tax column).
  Future<List<LiveChildItem>> loadItemsForOrder(String orderId,
      {String? checkId}) async {
    if (orderId.isEmpty) return const [];
    var query = _client
        .from('order_items')
        .select(
            'product_name, qty, quantity, subtotal, tax, discounts, status, order_item_modifiers(name, qty)')
        .eq('order_id', orderId);
    if (checkId != null && checkId.isNotEmpty) {
      query = query.eq('check_id', checkId);
    }
    final rows = await query;
    return List<Map<String, dynamic>>.from(rows)
        .where((row) => row['status']?.toString() != 'void')
        .map((row) {
          final modifiers = row['order_item_modifiers'] as List? ?? [];
          final extras = modifiers
              .map((m) => m is Map<String, dynamic> ? m['name']?.toString() : null)
              .whereType<String>()
              .toList();
          return LiveChildItem(
            name: row['product_name']?.toString() ?? 'Producto',
            quantity: _toDouble(row['qty'] ?? row['quantity']),
            total: _toDouble(row['subtotal']) +
                _toDouble(row['tax']) -
                _toDouble(row['discounts']),
            extras: extras,
          );
        })
        .toList(growable: false);
  }

  /// Mesero attributed to each comanda of [orderIds], resolved from the PIN
  /// typed on the account rather than from the user logged into the device.
  /// See `aggregateWaiterAttribution` for the priority chain.
  ///
  /// Keyed by `orderId` and by `orderId::checkId` for split bills. Lazy on
  /// purpose: only the comandas screen pays for these queries.
  Future<Map<String, List<TicketWaiter>>> loadWaitersForOrders({
    required String businessId,
    required List<String> orderIds,
  }) async {
    final ids =
        orderIds.where((id) => id.isNotEmpty).toSet().toList(growable: false);
    if (ids.isEmpty) return const {};

    final orderRowsFuture = _batchedInFilter(
      table: 'orders',
      select:
          'id, table_sessions!inner(id, opened_by_employee_id, waiter_user_id, opened_by)',
      filterColumn: 'id',
      values: ids,
    );
    final itemRowsFuture = _batchedInFilter(
      table: 'order_items',
      select:
          'order_id, check_id, status, subtotal, tax, discounts, created_by_employee_id',
      filterColumn: 'order_id',
      values: ids,
    );
    // Roster of the business: `employees.id` → name, and the
    // `user_id → employee` bridge the auth-user fallback needs. Tolerated as
    // empty if RLS ever blocks it — names then degrade, attribution doesn't.
    final rosterFuture = () async {
      try {
        final rows = await _client
            .from('employees')
            .select('id, first_name, last_name, user_id')
            .eq('business_id', businessId);
        return List<Map<String, dynamic>>.from(rows as List);
      } catch (_) {
        return const <Map<String, dynamic>>[];
      }
    }();

    final orderRows = await orderRowsFuture;
    final itemRows = await itemRowsFuture;
    final employeeRows = await rosterFuture;

    final userNames = await _resolveUserNames(
      waiterUserIdsToResolve(orderRows: orderRows, employeeRows: employeeRows)
          .toList(growable: false),
    );

    return aggregateWaiterAttribution(
      orderRows: orderRows,
      itemRows: itemRows,
      employeeRows: employeeRows,
      userNames: userNames,
    );
  }

  /// Loads the audit breakdown for a period: voided items, cancelled
  /// payments, and discounted orders. Used by the lazy `AuditDetailView`.
  /// Resolves waiter/cashier names via a single batched profiles query.
  Future<({AuditSummary summary, AuditDetail detail})> loadAuditDetail({
    required String businessId,
    required DateTime start,
    required DateTime end,
  }) async {
    final periodStart = start.toUtc().toIso8601String();
    final periodEnd = end.toUtc().toIso8601String();

    final results = await Future.wait([
      // Voided items in period — joined to orders → table_sessions for table
      // label, customer name, and waiter attribution.
      ReportRequestThrottle.run(() => _client
          .from('order_items')
          .select(
              'id, product_name, qty, quantity, subtotal, notes, orders!inner(id, created_at, table_sessions!inner(id, business_id, customer_name, waiter_user_id, dining_tables(label, code)))')
          .eq('status', 'void')
          .eq('orders.table_sessions.business_id', businessId)
          .gte('orders.created_at', periodStart)
          .lt('orders.created_at', periodEnd)),

      // Cancelled / voided payments in period.
      ReportRequestThrottle.run(() => _client
          .from('payments')
          .select(
              'id, amount, change_amount, status, created_at, processed_by, payment_methods(code), orders(id, table_sessions(dining_tables(label, code)))')
          .eq('business_id', businessId)
          .inFilter('status', ['void', 'cancelled'])
          .gte('created_at', periodStart)
          .lt('created_at', periodEnd)),

      // Orders with discount > 0.
      ReportRequestThrottle.run(() => _client
          .from('orders')
          .select(
              'id, total, discounts, created_at, table_sessions!inner(id, business_id, customer_name, waiter_user_id, dining_tables(label, code))')
          .eq('table_sessions.business_id', businessId)
          .gt('discounts', 0)
          .gte('created_at', periodStart)
          .lt('created_at', periodEnd)),

      // Whole orders voided in the period (mesa liberada / cuenta anulada),
      // by closed_at = the moment of the void. The [ANULACION] reason lives in
      // table_sessions.note.
      ReportRequestThrottle.run(() => _client
          .from('orders')
          .select(
              'id, total, created_at, closed_at, order_items(subtotal, tax, discounts), table_sessions!inner(id, business_id, customer_name, note, waiter_user_id, dining_tables(label, code))')
          .eq('table_sessions.business_id', businessId)
          .eq('status_ext', 'void')
          .or('closed_at.is.null,and(closed_at.gte.$periodStart,closed_at.lt.$periodEnd)')),
    ]);

    final voidRows = List<Map<String, dynamic>>.from(results[0]);
    final cancelRows = List<Map<String, dynamic>>.from(results[1]);
    final discountRows = List<Map<String, dynamic>>.from(results[2]);
    final cancelledOrderRows = List<Map<String, dynamic>>.from(results[3]);

    // Collect all user IDs we need to resolve names for.
    final userIds = <String>{};
    for (final row in voidRows) {
      final session = (row['orders'] is Map<String, dynamic>)
          ? row['orders']['table_sessions']
          : null;
      if (session is Map<String, dynamic>) {
        final id = session['waiter_user_id']?.toString();
        if (id != null && id.isNotEmpty) userIds.add(id);
      }
    }
    for (final row in cancelRows) {
      final id = row['processed_by']?.toString();
      if (id != null && id.isNotEmpty) userIds.add(id);
    }
    for (final row in discountRows) {
      final session = row['table_sessions'];
      if (session is Map<String, dynamic>) {
        final id = session['waiter_user_id']?.toString();
        if (id != null && id.isNotEmpty) userIds.add(id);
      }
    }
    for (final row in cancelledOrderRows) {
      final session = row['table_sessions'];
      if (session is Map<String, dynamic>) {
        final id = session['waiter_user_id']?.toString();
        if (id != null && id.isNotEmpty) userIds.add(id);
      }
    }

    final namesById = await _resolveUserNames(userIds.toList(growable: false));

    // Build VoidedItem list + accumulate KPIs.
    double voidedAmount = 0;
    final voidedItems = <VoidedItem>[];
    for (final row in voidRows) {
      final order = row['orders'];
      final session = order is Map<String, dynamic> ? order['table_sessions'] : null;
      final tableData = session is Map<String, dynamic> ? session['dining_tables'] : null;
      final amount = _toDouble(row['subtotal']);
      voidedAmount += amount;
      final waiterId = session is Map<String, dynamic>
          ? session['waiter_user_id']?.toString()
          : null;
      voidedItems.add(VoidedItem(
        orderItemId: row['id']?.toString() ?? '',
        productName: row['product_name']?.toString() ?? 'Producto',
        amount: amount,
        quantity: _toDouble(row['qty'] ?? row['quantity']),
        note: (row['notes']?.toString().trim().isNotEmpty ?? false)
            ? row['notes'].toString().trim()
            : null,
        createdAt: order is Map<String, dynamic>
            ? (DateTime.tryParse(order['created_at']?.toString() ?? '') ?? DateTime.now())
            : DateTime.now(),
        tableLabel: tableData is Map<String, dynamic>
            ? (tableData['label']?.toString() ?? tableData['code']?.toString())
            : null,
        customerName: session is Map<String, dynamic>
            ? session['customer_name']?.toString()
            : null,
        waiterName: waiterId != null ? namesById[waiterId] : null,
      ));
    }
    voidedItems.sort((a, b) => b.amount.compareTo(a.amount));

    // Build CancelledPayment list + KPIs.
    double cancelledAmount = 0;
    final cancelledPayments = <CancelledPayment>[];
    for (final row in cancelRows) {
      final amount = _netAmount(row['amount'], row['change_amount']);
      cancelledAmount += amount;
      final pm = row['payment_methods'];
      final order = row['orders'];
      final session = order is Map<String, dynamic> ? order['table_sessions'] : null;
      final tableData = session is Map<String, dynamic> ? session['dining_tables'] : null;
      final cashierId = row['processed_by']?.toString();
      cancelledPayments.add(CancelledPayment(
        paymentId: row['id']?.toString() ?? '',
        amount: amount,
        createdAt: DateTime.tryParse(row['created_at']?.toString() ?? '') ?? DateTime.now(),
        status: row['status']?.toString() ?? 'cancelled',
        methodCode: pm is Map<String, dynamic> ? pm['code']?.toString() : null,
        cashierName: cashierId != null ? namesById[cashierId] : null,
        tableLabel: tableData is Map<String, dynamic>
            ? (tableData['label']?.toString() ?? tableData['code']?.toString())
            : null,
      ));
    }
    cancelledPayments.sort((a, b) => b.createdAt.compareTo(a.createdAt));

    // Build DiscountedOrder list + KPIs.
    double discountsAmount = 0;
    final discountedOrders = <DiscountedOrder>[];
    for (final row in discountRows) {
      final discount = _toDouble(row['discounts']);
      discountsAmount += discount;
      final session = row['table_sessions'];
      final tableData = session is Map<String, dynamic> ? session['dining_tables'] : null;
      final waiterId = session is Map<String, dynamic>
          ? session['waiter_user_id']?.toString()
          : null;
      discountedOrders.add(DiscountedOrder(
        orderId: row['id']?.toString() ?? '',
        discount: discount,
        total: _toDouble(row['total']),
        createdAt: DateTime.tryParse(row['created_at']?.toString() ?? '') ?? DateTime.now(),
        tableLabel: tableData is Map<String, dynamic>
            ? (tableData['label']?.toString() ?? tableData['code']?.toString())
            : null,
        customerName: session is Map<String, dynamic>
            ? session['customer_name']?.toString()
            : null,
        waiterName: waiterId != null ? namesById[waiterId] : null,
      ));
    }
    discountedOrders.sort((a, b) => b.discount.compareTo(a.discount));

    // Build CancelledOrderAudit list (mesas liberadas / cuentas anuladas) with
    // their [ANULACION] notes.
    double cancelledOrdersAmount = 0;
    final cancelledOrders = <CancelledOrderAudit>[];
    for (final row in cancelledOrderRows) {
      final session = row['table_sessions'];
      final tableData =
          session is Map<String, dynamic> ? session['dining_tables'] : null;
      // Worth of the account when voided: every line, whatever its status.
      var amount = 0.0;
      final items = row['order_items'];
      if (items is List) {
        for (final it in items) {
          if (it is! Map) continue;
          amount += _toDouble(it['subtotal']) +
              _toDouble(it['tax']) -
              _toDouble(it['discounts']);
        }
      }
      if (amount <= 0) amount = _toDouble(row['total']);
      cancelledOrdersAmount += amount;
      final waiterId = session is Map<String, dynamic>
          ? session['waiter_user_id']?.toString()
          : null;
      cancelledOrders.add(CancelledOrderAudit(
        orderId: row['id']?.toString() ?? '',
        amount: amount,
        createdAt: DateTime.tryParse(row['created_at']?.toString() ?? '') ??
            DateTime.now(),
        closedAt: DateTime.tryParse(row['closed_at']?.toString() ?? ''),
        tableLabel: tableData is Map<String, dynamic>
            ? (tableData['label']?.toString() ?? tableData['code']?.toString())
            : null,
        customerName: session is Map<String, dynamic>
            ? session['customer_name']?.toString()
            : null,
        waiterName: waiterId != null ? namesById[waiterId] : null,
        notes: CancellationNote.parseAll(
            session is Map<String, dynamic> ? session['note']?.toString() : null),
      ));
    }
    cancelledOrders.sort((a, b) =>
        (b.closedAt ?? b.createdAt).compareTo(a.closedAt ?? a.createdAt));

    final summary = AuditSummary(
      voidedAmount: voidedAmount,
      voidedItemsCount: voidedItems.length,
      cancelledAmount: cancelledAmount,
      cancelledPaymentsCount: cancelledPayments.length,
      discountsAmount: discountsAmount,
      discountsAppliedCount: discountedOrders.length,
      cancelledOrdersAmount: cancelledOrdersAmount,
      cancelledOrdersCount: cancelledOrders.length,
    );

    return (
      summary: summary,
      detail: AuditDetail(
        voidedItems: voidedItems,
        cancelledPayments: cancelledPayments,
        discountedOrders: discountedOrders,
        cancelledOrders: cancelledOrders,
      ),
    );
  }

  /// Loads the table sessions a specific waiter served in [start..end].
  /// Each row represents a mesa with its order total.
  Future<List<PersonSession>> loadSessionsForWaiter({
    required String businessId,
    required String waiterUserId,
    required DateTime start,
    required DateTime end,
  }) async {
    final rows = await _client
        .from('table_sessions')
        .select('''
          id, opened_at, closed_at, customer_name, people_count, origin,
          dining_tables(id, label, code, zones(name)),
          orders(id, payments(amount, change_amount, status))
        ''')
        .eq('business_id', businessId)
        .eq('waiter_user_id', waiterUserId)
        .gte('opened_at', start.toUtc().toIso8601String())
        .lt('opened_at', end.toUtc().toIso8601String())
        .order('opened_at', ascending: false);

    return List<Map<String, dynamic>>.from(rows).map((row) {
      final table = row['dining_tables'];
      final zones = table is Map<String, dynamic> ? table['zones'] : null;
      // Total = net of completed payments for this session's orders. Matches the
      // waiter-performance card and the canonical sales scope. `orders.total` is
      // unreliable (often 0) across POS flows, so we never use it here.
      double total = 0;
      final orders = row['orders'];
      if (orders is List) {
        for (final o in orders) {
          if (o is! Map<String, dynamic>) continue;
          final payments = o['payments'];
          if (payments is! List) continue;
          for (final p in payments) {
            if (p is! Map<String, dynamic>) continue;
            final status = p['status']?.toString();
            if (status == 'void' || status == 'cancelled') continue;
            total += _netAmount(p['amount'], p['change_amount']);
          }
        }
      }
      return PersonSession(
        sessionId: row['id']?.toString() ?? '',
        tableLabel: table is Map<String, dynamic>
            ? (table['label']?.toString() ?? table['code']?.toString() ?? 'Mesa')
            : 'Sesión',
        zoneName: zones is Map<String, dynamic> ? zones['name']?.toString() : null,
        openedAt: DateTime.tryParse(row['opened_at']?.toString() ?? '') ?? DateTime.now(),
        closedAt: DateTime.tryParse(row['closed_at']?.toString() ?? ''),
        customerName: row['customer_name']?.toString(),
        peopleCount: row['people_count'] is int
            ? row['people_count'] as int
            : int.tryParse(row['people_count']?.toString() ?? ''),
        total: total,
        origin: row['origin']?.toString(),
      );
    }).toList(growable: false);
  }

  /// Loads payments processed by a specific cashier in [start..end], expanding
  /// each into a [PersonSession] (one row per payment, with the mesa's metadata).
  Future<List<PersonSession>> loadPaymentsForCashier({
    required String businessId,
    required String cashierUserId,
    required DateTime start,
    required DateTime end,
  }) async {
    final rows = await _client
        .from('payments')
        .select('''
          id, amount, change_amount, status, created_at,
          payment_methods(code),
          orders!inner(
            id,
            table_sessions!inner(
              id, opened_at, closed_at, customer_name, people_count, origin,
              dining_tables(id, label, code, zones(name))
            )
          )
        ''')
        .eq('business_id', businessId)
        .eq('processed_by', cashierUserId)
        .gte('created_at', start.toUtc().toIso8601String())
        .lt('created_at', end.toUtc().toIso8601String())
        .not('status', 'in', '(void,cancelled)')
        .order('created_at', ascending: false);

    // Group payments by session → ONE row per table. A divided account paid with
    // several check payments becomes a single row with the summed amount, instead
    // of one partial row per payment.
    final bySession = <String, _CashierSessionAgg>{};
    for (final row in List<Map<String, dynamic>>.from(rows)) {
      final order = row['orders'];
      final session = order is Map<String, dynamic> ? order['table_sessions'] : null;
      final sid =
          session is Map<String, dynamic> ? session['id']?.toString() ?? '' : '';
      final key = sid.isNotEmpty ? sid : 'pay_${row['id']}';
      final agg = bySession.putIfAbsent(key, () => _CashierSessionAgg(row));
      agg.total += _netAmount(row['amount'], row['change_amount']);
      final pm = row['payment_methods'];
      final code = pm is Map<String, dynamic> ? pm['code']?.toString() : null;
      if (code != null && code.isNotEmpty) agg.codes.add(code);
      final created = DateTime.tryParse(row['created_at']?.toString() ?? '');
      if (created != null &&
          (agg.lastPaidAt == null || created.isAfter(agg.lastPaidAt!))) {
        agg.lastPaidAt = created;
      }
    }

    final result = bySession.values.map((agg) {
      final row = agg.row;
      final order = row['orders'];
      final session = order is Map<String, dynamic> ? order['table_sessions'] : null;
      final table = session is Map<String, dynamic> ? session['dining_tables'] : null;
      final zones = table is Map<String, dynamic> ? table['zones'] : null;
      return PersonSession(
        sessionId:
            session is Map<String, dynamic> ? session['id']?.toString() ?? '' : '',
        tableLabel: table is Map<String, dynamic>
            ? (table['label']?.toString() ?? table['code']?.toString() ?? 'Mesa')
            : 'Pago',
        zoneName: zones is Map<String, dynamic> ? zones['name']?.toString() : null,
        openedAt: agg.lastPaidAt ?? DateTime.now(),
        closedAt: session is Map<String, dynamic>
            ? DateTime.tryParse(session['closed_at']?.toString() ?? '')
            : null,
        customerName: session is Map<String, dynamic>
            ? session['customer_name']?.toString()
            : null,
        peopleCount: session is Map<String, dynamic> &&
                (session['people_count'] is int ||
                    int.tryParse(session['people_count']?.toString() ?? '') != null)
            ? (session['people_count'] is int
                ? session['people_count'] as int
                : int.tryParse(session['people_count']?.toString() ?? ''))
            : null,
        total: agg.total,
        paymentMethodCode: agg.codes.length == 1 ? agg.codes.first : null,
        origin: session is Map<String, dynamic> ? session['origin']?.toString() : null,
      );
    }).toList();
    result.sort((a, b) => b.openedAt.compareTo(a.openedAt));
    return result;
  }

  /// Loads zones + their dining tables for the visual table map.
  Future<List<ZoneLayout>> loadTableLayout(String businessId) async {
    final rows = await _client
        .from('zones')
        .select('id, name, sort_index, is_active, dining_tables(id, label, code, capacity, shape, is_active, zone_id)')
        .eq('business_id', businessId)
        .eq('is_active', true)
        .order('sort_index', ascending: true);

    final result = <ZoneLayout>[];
    for (final row in List<Map<String, dynamic>>.from(rows)) {
      final zoneId = row['id']?.toString() ?? '';
      final zoneName = row['name']?.toString() ?? 'Zona';
      final sortIndex = row['sort_index'] is int
          ? row['sort_index'] as int
          : int.tryParse(row['sort_index']?.toString() ?? '') ?? 0;
      final rawTables = row['dining_tables'] as List? ?? [];
      final tables = rawTables
          .whereType<Map<String, dynamic>>()
          .where((t) => t['is_active'] != false)
          .map((t) => TableLayoutItem(
                id: t['id']?.toString() ?? '',
                label: t['label']?.toString() ?? t['code']?.toString() ?? 'Mesa',
                zoneId: zoneId,
                zoneName: zoneName,
                capacity: t['capacity'] is int
                    ? t['capacity'] as int
                    : int.tryParse(t['capacity']?.toString() ?? ''),
                shape: t['shape']?.toString(),
                isActive: t['is_active'] != false,
              ))
          .toList()
        ..sort((a, b) => a.label.compareTo(b.label));
      if (tables.isEmpty) continue;
      result.add(ZoneLayout(
        id: zoneId,
        name: zoneName,
        sortIndex: sortIndex,
        tables: tables,
      ));
    }
    return result;
  }

  double _netAmount(dynamic amount, dynamic changeAmount) {
    return _toDouble(amount) - _toDouble(changeAmount);
  }

  double _toDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }

  double? _toDoubleOrNull(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString());
  }

}

class _WaiterAgg {
  double total = 0;
  int ticketCount = 0;
  final Set<String> sessions = <String>{};
}

/// Accumulates a cashier's payments for one dining session (table) so a split
/// account paid across several checks becomes a single row.
class _CashierSessionAgg {
  _CashierSessionAgg(this.row);
  final Map<String, dynamic> row; // representative payment row (carries metadata)
  double total = 0;
  final Set<String> codes = <String>{};
  DateTime? lastPaidAt;
}

class _CashierAgg {
  double total = 0;
  int ticketCount = 0;
  final Set<String> orderIds = <String>{};
}

class _ModifierAgg {
  double count = 0;
  double revenue = 0;
}

class _CustomerAgg {
  double totalSpent = 0;
  final Set<String> orderIds = <String>{};
  int bareVisits = 0;
  DateTime? firstVisit;
  DateTime? lastVisit;
  String? displayName;
  String? rnc;
}
