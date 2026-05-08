import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/auth/admin_access_profile.dart';
import '../../domain/dashboard/dashboard_models.dart';

class DashboardDataService {
  DashboardDataService(this._client);

  final SupabaseClient _client;
  static const _batchSize = 40;

  /// Executes a query with `.inFilter()` in batches to avoid URI-too-long errors.
  /// Batches run in parallel for speed.
  Future<List<Map<String, dynamic>>> _batchedInFilter({
    required String table,
    required String select,
    required String filterColumn,
    required List<String> values,
  }) async {
    if (values.isEmpty) return [];
    final futures = <Future<List<dynamic>>>[];
    for (var i = 0; i < values.length; i += _batchSize) {
      final chunk = values.sublist(i, i + _batchSize > values.length ? values.length : i + _batchSize);
      futures.add(_client.from(table).select(select).inFilter(filterColumn, chunk));
    }
    final batches = await Future.wait(futures);
    final results = <Map<String, dynamic>>[];
    for (final batch in batches) {
      results.addAll(List<Map<String, dynamic>>.from(batch));
    }
    return results;
  }

  /// Loads dashboard data. Set [liteMode] to true to skip catalog, active orders,
  /// closed orders, and previous-period comparison — useful for the sales-only view.
  Future<DashboardSummary> loadSummary(AdminAccessProfile profile, {
    SalesDateFilter filter = SalesDateFilter.month,
    DateTimeRange? customRange,
    bool liteMode = false,
  }) async {
    final businessId = profile.businessId;
    final now = DateTime.now();
    
    DateTime start;
    DateTime end;
    DateTime prevStart;
    DateTime prevEnd;

    switch (filter) {
      case SalesDateFilter.today:
        start = DateTime(now.year, now.month, now.day);
        end = start.add(const Duration(days: 1));
        prevStart = start.subtract(const Duration(days: 1));
        prevEnd = start;
        break;
      case SalesDateFilter.yesterday:
        start = DateTime(now.year, now.month, now.day).subtract(const Duration(days: 1));
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
        start = customRange?.start ?? now;
        end = customRange?.end ?? now.add(const Duration(days: 1));
        // Para comparación previa en custom, usamos el mismo periodo de tiempo hacia atrás
        final diff = end.difference(start);
        prevStart = start.subtract(diff);
        prevEnd = start;
        break;
    }

    final periodStart = start.toUtc().toIso8601String();
    final periodEnd = end.toUtc().toIso8601String();

    // ── Phase 1: Fire independent queries in parallel ──
    // Period payments are filtered directly by business_id, so derived order_ids
    // are inherently business-scoped — no extra scoping round-trip needed.
    final pStart = prevStart.toUtc().toIso8601String();
    final pEnd = prevEnd.toUtc().toIso8601String();

    final periodPaymentsFuture = _client.from('payments')
        .select('amount, change_amount, status, order_id, created_at, processed_by, payment_methods(code)')
        .eq('business_id', businessId)
        .gte('created_at', periodStart).lt('created_at', periodEnd);

    // Previous period payments — small payload, kept even in liteMode for growth chip.
    final prevPaymentsFuture = _client.from('payments')
        .select('amount, change_amount, status, created_at')
        .eq('business_id', businessId)
        .gte('created_at', pStart).lt('created_at', pEnd);

    final futures = <Future<List<dynamic>>>[periodPaymentsFuture, prevPaymentsFuture];
    if (!liteMode) {
      futures.addAll([
        // Active Orders (all of them, regardless of date)
        _client.from('orders')
            .select('id, total, status_ext, created_at, closed_at, table_sessions!inner(id, business_id, customer_name, opened_at, people_count, origin, dining_tables(*)), order_items(product_name, qty, quantity, total, order_item_modifiers(name, qty))')
            .eq('table_sessions.business_id', businessId)
            .isFilter('closed_at', null)
            .order('created_at', ascending: false).limit(1000),
        // Catalog
        _client.from('menu_items')
            .select('id, name, price, is_active, categories(name), menu_item_groups(modifier_groups(id, name, selection_mode, modifiers(id, name, price_delta, is_active)))')
            .eq('business_id', businessId).order('name', ascending: true),
        // Closed Orders for the period
        _client.from('orders')
            .select('id, total, status_ext, created_at, closed_at, table_sessions!inner(id, business_id, customer_name, opened_at, people_count, origin, dining_tables(*)), order_items(product_name, qty, quantity, total, order_item_modifiers(name, qty))')
            .eq('table_sessions.business_id', businessId)
            .gte('closed_at', periodStart)
            .lt('closed_at', periodEnd)
            .order('closed_at', ascending: false).limit(500),
      ]);
    }

    final results = await Future.wait(futures);

    final paymentRows = List<Map<String, dynamic>>.from(results[0]);
    final prevPaymentRows = List<Map<String, dynamic>>.from(results[1]);
    final activeOrdersRaw = liteMode ? const <Map<String, dynamic>>[] : List<Map<String, dynamic>>.from(results[2]);
    final productsRaw = liteMode ? const <Map<String, dynamic>>[] : List<Map<String, dynamic>>.from(results[3]);
    final closedOrdersRaw = liteMode ? const <Map<String, dynamic>>[] : List<Map<String, dynamic>>.from(results[4]);

    // Order IDs from period payments are inherently business-scoped (payments filtered by business_id)
    final scopedOrderIds = paymentRows
        .map((row) => row['order_id']?.toString())
        .whereType<String>().where((id) => id.isNotEmpty).toSet();

    // ── Phase 3: Process results (CPU-only, no awaits) ──

    // Period sales & tickets
    double totalSales = 0;
    final tickets = <TicketItem>[];
    for (final row in paymentRows) {
      final oid = row['order_id']?.toString();
      if (!scopedOrderIds.contains(oid)) continue;
      final status = row['status']?.toString();
      if (status == 'void' || status == 'cancelled') continue;
      final net = _netAmount(row['amount'], row['change_amount']);
      totalSales += net;
      final pm = row['payment_methods'];
      final pmCode = pm is Map<String, dynamic> ? pm['code']?.toString() : null;
      tickets.add(TicketItem(
        orderId: oid ?? '',
        amount: net,
        createdAt: DateTime.tryParse(row['created_at']?.toString() ?? '') ?? DateTime.now(),
        paymentMethodCode: pmCode,
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
      liveOrders.add(_mapToLiveOrderItem(row));
    }

    // Part B: Process Closed Orders
    for (final row in closedOrdersRaw) {
      closedOrders.add(_mapToLiveOrderItem(row));
    }

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

    // ── Phase 4: Top products & Category aggregation (needs scopedOrderIds) ──
    final topProductsRaw = await _batchedInFilter(
      table: 'order_items',
      select: 'order_id, product_name, quantity, qty, total, status, menu_items(categories(name))',
      filterColumn: 'order_id',
      values: scopedOrderIds.toList(),
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
      if (!scopedOrderIds.contains(row['order_id']?.toString())) continue;
      final status = row['status']?.toString();
      if (status == 'void' || status == 'cancelled') continue;
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

    // Previous period comparison (already business-scoped via business_id filter)
    double previousDaySales = 0;
    for (final row in prevPaymentRows) {
      final status = row['status']?.toString();
      if (status == 'void' || status == 'cancelled') continue;
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

    // ── Waiter performance: map orderId → waiter via table_sessions, then
    // aggregate the period's payments per waiter and resolve profile names.
    final paymentOrderIds = paymentRows
        .map((p) => p['order_id']?.toString())
        .whereType<String>()
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList(growable: false);

    final performanceResults = await Future.wait([
      _loadWaiterPerformance(
        paymentRows: paymentRows,
        paymentOrderIds: paymentOrderIds,
      ),
      _loadCashierPerformance(paymentRows: paymentRows),
    ]);
    final waiterPerformance = performanceResults[0] as List<WaiterPerformance>;
    final cashierPerformance = performanceResults[1] as List<CashierPerformance>;

    final activeOrdersCount = liveOrders.length;
    // Tickets are payment-driven, not order-driven: this keeps the count
    // consistent with `totalSales` (also derived from `paymentRows`) and
    // works in liteMode (which skips the closed-orders query).
    final totalTickets = tickets.length;

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
  /// and resolves their display names. Excludes void/cancelled payments and
  /// payments without an assigned cashier.
  Future<List<CashierPerformance>> _loadCashierPerformance({
    required List<Map<String, dynamic>> paymentRows,
  }) async {
    final agg = <String, _CashierAgg>{};
    for (final row in paymentRows) {
      final processedBy = row['processed_by']?.toString();
      if (processedBy == null || processedBy.isEmpty) continue;
      final status = row['status']?.toString();
      if (status == 'void' || status == 'cancelled') continue;
      final net = _netAmount(row['amount'], row['change_amount']);
      final orderId = row['order_id']?.toString();
      final entry = agg.putIfAbsent(processedBy, _CashierAgg.new);
      entry.total += net;
      entry.ticketCount += 1;
      if (orderId != null && orderId.isNotEmpty) entry.orderIds.add(orderId);
    }
    if (agg.isEmpty) return const [];

    final cashierIds = agg.keys.toList(growable: false);
    final profileRows = await _batchedInFilter(
      table: 'profiles',
      select: 'id, full_name',
      filterColumn: 'id',
      values: cashierIds,
    );
    final namesById = <String, String>{};
    for (final row in profileRows) {
      final id = row['id']?.toString();
      final name = row['full_name']?.toString().trim();
      if (id != null && name != null && name.isNotEmpty) namesById[id] = name;
    }

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
    final profileRows = await _batchedInFilter(
      table: 'profiles',
      select: 'id, full_name',
      filterColumn: 'id',
      values: waiterIds,
    );
    final namesById = <String, String>{};
    for (final row in profileRows) {
      final id = row['id']?.toString();
      final name = row['full_name']?.toString().trim();
      if (id != null && name != null && name.isNotEmpty) namesById[id] = name;
    }

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

  LiveOrderItem _mapToLiveOrderItem(Map<String, dynamic> row) {
    final session = row['table_sessions'];
    final tableData = session is Map<String, dynamic> ? session['dining_tables'] : null;
    final tableLabel = tableData is Map<String, dynamic>
        ? (tableData['label']?.toString() ?? tableData['code']?.toString() ?? 'Mesa')
        : 'Orden';
    final tableId = tableData is Map<String, dynamic> ? tableData['id']?.toString() : null;
    final customerName = session is Map<String, dynamic>
        ? session['customer_name']?.toString()
        : null;
    final openedAt = session is Map<String, dynamic>
        ? DateTime.tryParse(session['opened_at']?.toString() ?? '')
        : null;
    final peopleCount = session is Map<String, dynamic>
        ? (session['people_count'] is int
            ? session['people_count'] as int
            : int.tryParse(session['people_count']?.toString() ?? ''))
        : null;

    final rawItems = row['order_items'] as List? ?? [];
    final childItems = rawItems.map((ri) {
      final modifiers = ri['order_item_modifiers'] as List? ?? [];
      final extras = modifiers.map((m) => m['name']?.toString()).whereType<String>().toList();
      return LiveChildItem(
        name: ri['product_name']?.toString() ?? 'Producto',
        quantity: _toDouble(ri['qty'] ?? ri['quantity']),
        total: _toDouble(ri['total']),
        extras: extras,
      );
    }).toList();

    final zone = tableData is Map<String, dynamic>
        ? (tableData['zone_name']?.toString() ??
            tableData['zone']?.toString() ??
            tableData['area_name']?.toString() ??
            tableData['area']?.toString())
        : null;

    return LiveOrderItem(
      id: row['id']?.toString() ?? '',
      title: tableLabel,
      subtitle: customerName ?? row['status_ext']?.toString() ?? 'open',
      total: _toDouble(row['total']),
      status: row['status_ext']?.toString() ?? 'open',
      items: childItems,
      zone: zone,
      tableId: tableId,
      openedAt: openedAt,
      peopleCount: peopleCount,
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
      _client
          .from('order_items')
          .select(
              'id, product_name, qty, quantity, subtotal, orders!inner(id, created_at, table_sessions!inner(id, business_id, customer_name, waiter_user_id, dining_tables(label, code)))')
          .eq('status', 'void')
          .eq('orders.table_sessions.business_id', businessId)
          .gte('orders.created_at', periodStart)
          .lt('orders.created_at', periodEnd),

      // Cancelled / voided payments in period.
      _client
          .from('payments')
          .select(
              'id, amount, change_amount, status, created_at, processed_by, payment_methods(code), orders(id, table_sessions(dining_tables(label, code)))')
          .eq('business_id', businessId)
          .inFilter('status', ['void', 'cancelled'])
          .gte('created_at', periodStart)
          .lt('created_at', periodEnd),

      // Orders with discount > 0.
      _client
          .from('orders')
          .select(
              'id, total, discounts, created_at, table_sessions!inner(id, business_id, customer_name, waiter_user_id, dining_tables(label, code))')
          .eq('table_sessions.business_id', businessId)
          .gt('discounts', 0)
          .gte('created_at', periodStart)
          .lt('created_at', periodEnd),
    ]);

    final voidRows = List<Map<String, dynamic>>.from(results[0]);
    final cancelRows = List<Map<String, dynamic>>.from(results[1]);
    final discountRows = List<Map<String, dynamic>>.from(results[2]);

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

    final namesById = <String, String>{};
    if (userIds.isNotEmpty) {
      final profileRows = await _batchedInFilter(
        table: 'profiles',
        select: 'id, full_name',
        filterColumn: 'id',
        values: userIds.toList(growable: false),
      );
      for (final row in profileRows) {
        final id = row['id']?.toString();
        final name = row['full_name']?.toString().trim();
        if (id != null && name != null && name.isNotEmpty) namesById[id] = name;
      }
    }

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

    final summary = AuditSummary(
      voidedAmount: voidedAmount,
      voidedItemsCount: voidedItems.length,
      cancelledAmount: cancelledAmount,
      cancelledPaymentsCount: cancelledPayments.length,
      discountsAmount: discountsAmount,
      discountsAppliedCount: discountedOrders.length,
    );

    return (
      summary: summary,
      detail: AuditDetail(
        voidedItems: voidedItems,
        cancelledPayments: cancelledPayments,
        discountedOrders: discountedOrders,
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
          orders(total)
        ''')
        .eq('business_id', businessId)
        .eq('waiter_user_id', waiterUserId)
        .gte('opened_at', start.toUtc().toIso8601String())
        .lt('opened_at', end.toUtc().toIso8601String())
        .order('opened_at', ascending: false);

    return List<Map<String, dynamic>>.from(rows).map((row) {
      final table = row['dining_tables'];
      final zones = table is Map<String, dynamic> ? table['zones'] : null;
      double total = 0;
      final orders = row['orders'];
      if (orders is List) {
        for (final o in orders) {
          if (o is Map<String, dynamic>) total += _toDouble(o['total']);
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

    return List<Map<String, dynamic>>.from(rows).map((row) {
      final order = row['orders'];
      final session = order is Map<String, dynamic> ? order['table_sessions'] : null;
      final table = session is Map<String, dynamic> ? session['dining_tables'] : null;
      final zones = table is Map<String, dynamic> ? table['zones'] : null;
      final pm = row['payment_methods'];
      final code = pm is Map<String, dynamic> ? pm['code']?.toString() : null;
      final net = _netAmount(row['amount'], row['change_amount']);
      return PersonSession(
        sessionId: session is Map<String, dynamic> ? session['id']?.toString() ?? '' : '',
        tableLabel: table is Map<String, dynamic>
            ? (table['label']?.toString() ?? table['code']?.toString() ?? 'Mesa')
            : 'Pago',
        zoneName: zones is Map<String, dynamic> ? zones['name']?.toString() : null,
        openedAt: DateTime.tryParse(row['created_at']?.toString() ?? '') ?? DateTime.now(),
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
        total: net,
        paymentMethodCode: code,
        origin: session is Map<String, dynamic> ? session['origin']?.toString() : null,
      );
    }).toList(growable: false);
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

class _CashierAgg {
  double total = 0;
  int ticketCount = 0;
  final Set<String> orderIds = <String>{};
}
