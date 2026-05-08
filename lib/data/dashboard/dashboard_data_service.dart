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
        .select('amount, change_amount, status, order_id, created_at, payment_methods(code)')
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

    final activeOrdersCount = liveOrders.length;
    final closedOrdersCount = closedOrders.length;
    final totalTickets = activeOrdersCount + closedOrdersCount;

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
    );
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
