import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/auth/admin_access_profile.dart';
import '../../domain/dashboard/dashboard_models.dart';

class DashboardDataService {
  DashboardDataService(this._client);

  final SupabaseClient _client;
  static const _batchSize = 40;

  /// Executes a query with `.inFilter()` in batches to avoid URI-too-long errors.
  Future<List<Map<String, dynamic>>> _batchedInFilter({
    required String table,
    required String select,
    required String filterColumn,
    required List<String> values,
  }) async {
    if (values.isEmpty) return [];
    final results = <Map<String, dynamic>>[];
    for (var i = 0; i < values.length; i += _batchSize) {
      final chunk = values.sublist(i, i + _batchSize > values.length ? values.length : i + _batchSize);
      final rows = await _client
          .from(table)
          .select(select)
          .inFilter(filterColumn, chunk);
      results.addAll(List<Map<String, dynamic>>.from(rows));
    }
    return results;
  }

  Future<DashboardSummary> loadSummary(AdminAccessProfile profile, {SalesDateFilter filter = SalesDateFilter.month}) async {
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
    }

    final periodStart = start.toUtc().toIso8601String();
    final periodEnd = end.toUtc().toIso8601String();

    // ── Phase 1: Fire independent queries in parallel ──
    final todayStart = DateTime(now.year, now.month, now.day).toUtc().toIso8601String();
    final tomorrowStart = DateTime(now.year, now.month, now.day + 1).toUtc().toIso8601String();
    final pStart = prevStart.toUtc().toIso8601String();
    final pEnd = prevEnd.toUtc().toIso8601String();

    final results = await Future.wait([
      // [0] Period payments
      _client.from('payments')
          .select('amount, change_amount, status, order_id, created_at, payment_methods(code)')
          .gte('created_at', periodStart).lt('created_at', periodEnd),
      // [1] Orders (both active and recently closed for the period)
      _client.from('orders')
          .select('id, total, status_ext, created_at, closed_at, table_sessions!inner(id, business_id, customer_name, dining_tables(code, label)), order_items(product_name, qty, quantity, total, order_item_modifiers(name, qty))')
          .eq('table_sessions.business_id', businessId)
          .gte('created_at', periodStart)
          .lt('created_at', periodEnd)
          .order('created_at', ascending: false).limit(60),
      // [2] Catalog
      _client.from('menu_items')
          .select('id, name, price, is_active, categories(name), menu_item_groups(modifier_groups(id, name, selection_mode, modifiers(id, name, price_delta, is_active)))')
          .eq('business_id', businessId).order('name', ascending: true),
      // [3] Today payments (for hourly + method breakdown)
      _client.from('payments')
          .select('amount, change_amount, status, order_id, created_at, payment_methods(code)')
          .gte('created_at', todayStart).lt('created_at', tomorrowStart),
      // [4] Previous period payments
      _client.from('payments')
          .select('amount, change_amount, status, order_id, created_at')
          .gte('created_at', pStart).lt('created_at', pEnd),
    ]);

    final paymentRows = List<Map<String, dynamic>>.from(results[0]);
    final activeOrdersRaw = List<Map<String, dynamic>>.from(results[1]);
    final productsRaw = List<Map<String, dynamic>>.from(results[2]);
    final todayPayments = List<Map<String, dynamic>>.from(results[3]);
    final prevPaymentRows = List<Map<String, dynamic>>.from(results[4]);

    // ── Phase 2: Scope order IDs to business (parallel batches) ──
    final orderIds = paymentRows
        .map((row) => row['order_id']?.toString())
        .whereType<String>().where((id) => id.isNotEmpty).toSet().toList(growable: false);
    final todayOrderIds = todayPayments
        .map((row) => row['order_id']?.toString())
        .whereType<String>().where((id) => id.isNotEmpty).toSet().toList(growable: false);
    final prevOrderIds = prevPaymentRows
        .map((row) => row['order_id']?.toString())
        .whereType<String>().where((id) => id.isNotEmpty).toSet().toList(growable: false);

    // All three scoping queries can run in parallel
    final scopeResults = await Future.wait([
      _scopeOrderIds(orderIds, businessId),
      _scopeOrderIds(todayOrderIds, businessId),
      _scopeOrderIds(prevOrderIds, businessId),
    ]);
    final scopedOrderIds = scopeResults[0];
    final scopedTodayOrderIds = scopeResults[1];
    final scopedPrevOrderIds = scopeResults[2];

    // ── Phase 3: Process results (CPU-only, no awaits) ──

    // Period sales & tickets
    double totalSales = 0;
    int totalTickets = 0;
    final tickets = <TicketItem>[];
    for (final row in paymentRows) {
      final oid = row['order_id']?.toString();
      if (!scopedOrderIds.contains(oid)) continue;
      final status = row['status']?.toString();
      if (status == 'void' || status == 'cancelled') continue;
      final net = _netAmount(row['amount'], row['change_amount']);
      totalSales += net;
      totalTickets += 1;
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
    for (final row in activeOrdersRaw) {
      final isClosed = row['closed_at'] != null;
      final session = row['table_sessions'];
      final tableData = session is Map<String, dynamic> ? session['dining_tables'] : null;
      final tableLabel = tableData is Map<String, dynamic>
          ? (tableData['label']?.toString() ?? tableData['code']?.toString() ?? 'Mesa')
          : 'Orden';
      final customerName = session is Map<String, dynamic>
          ? session['customer_name']?.toString()
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

      final item = LiveOrderItem(
        id: row['id']?.toString() ?? '',
        title: tableLabel,
        subtitle: customerName ?? row['status_ext']?.toString() ?? 'open',
        total: _toDouble(row['total']),
        status: row['status_ext']?.toString() ?? 'open',
        items: childItems,
      );

      if (isClosed) {
        closedOrders.add(item);
      } else {
        liveOrders.add(item);
      }
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

    // ── Phase 4: Top products (needs scopedOrderIds) ──
    final topProductsRaw = await _batchedInFilter(
      table: 'order_items',
      select: 'order_id, product_name, quantity, qty, total, status',
      filterColumn: 'order_id',
      values: scopedOrderIds.toList(),
    );

    final Map<String, TopProduct> aggregate = {};
    for (final row in topProductsRaw) {
      if (row['status']?.toString() == 'void') continue;
      final label = row['product_name']?.toString().trim().isNotEmpty == true
          ? row['product_name'].toString().trim()
          : 'Producto';
      final current = aggregate[label];
      final nextAmount = (current?.amount ?? 0) + _toDouble(row['total']);
      final nextQty = (current?.quantity ?? 0) + _toDouble(row['qty'] ?? row['quantity']);
      aggregate[label] = TopProduct(label: label, amount: nextAmount, quantity: nextQty);
    }
    final topProducts = aggregate.values.toList()
      ..sort((a, b) => b.amount.compareTo(a.amount));

    // Hourly sales + method breakdown (today)
    final Map<int, double> hourlyMap = {};
    final Map<String, double> methodTotals = {};
    for (final row in todayPayments) {
      if (!scopedTodayOrderIds.contains(row['order_id']?.toString())) continue;
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

    // Previous period comparison
    double previousDaySales = 0;
    for (final row in prevPaymentRows) {
      if (!scopedPrevOrderIds.contains(row['order_id']?.toString())) continue;
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

    return DashboardSummary(
      profile: profile,
      totalSales: totalSales,
      totalTickets: totalTickets,
      averageTicket: totalTickets == 0 ? 0 : totalSales / totalTickets,
      activeOrders: liveOrders.length,
      topProducts: topProducts.take(5).toList(growable: false),
      catalogItems: catalogItems,
      liveOrders: liveOrders,
      closedOrders: closedOrders,
      pendingAmount: pendingAmount,
      previousDaySales: previousDaySales,
      hourlySales: hourlySales,
      salesByMethod: salesByMethod,
      topSeller: topSeller,
      filter: filter,
      tickets: tickets,
      pendingTables: pendingTables,
    );
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

  Future<Set<String>> _scopeOrderIds(List<String> orderIds, String businessId) async {
    if (orderIds.isEmpty) return const {};
    final result = <String>{};
    for (var i = 0; i < orderIds.length; i += _batchSize) {
      final chunk = orderIds.sublist(i, i + _batchSize > orderIds.length ? orderIds.length : i + _batchSize);
      final scoped = await _client
          .from('orders')
          .select('id, table_sessions!inner(business_id)')
          .inFilter('id', chunk)
          .eq('table_sessions.business_id', businessId);
      for (final row in List<Map<String, dynamic>>.from(scoped)) {
        final id = row['id']?.toString();
        if (id != null && id.isNotEmpty) result.add(id);
      }
    }
    return result;
  }
}
