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

    final paymentsRaw = await _client
        .from('payments')
        .select('amount, change_amount, status, order_id, created_at')
        .gte('created_at', periodStart)
        .lt('created_at', periodEnd);

    final paymentRows = List<Map<String, dynamic>>.from(paymentsRaw);
    final orderIds = paymentRows
        .map((row) => row['order_id']?.toString())
        .whereType<String>()
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList(growable: false);

    final scopedOrderIds = <String>{};
    if (orderIds.isNotEmpty) {
      // Batch to avoid URI-too-long with many order IDs.
      for (var i = 0; i < orderIds.length; i += _batchSize) {
        final chunk = orderIds.sublist(i, i + _batchSize > orderIds.length ? orderIds.length : i + _batchSize);
        final scoped = await _client
            .from('orders')
            .select('id, table_sessions!inner(business_id)')
            .inFilter('id', chunk)
            .eq('table_sessions.business_id', businessId);
        for (final row in List<Map<String, dynamic>>.from(scoped)) {
          final id = row['id']?.toString();
          if (id != null && id.isNotEmpty) scopedOrderIds.add(id);
        }
      }
    }

    double totalSales = 0;
    int totalTickets = 0;
    final tickets = <TicketItem>[];
    for (final row in paymentRows) {
      if (!scopedOrderIds.contains(row['order_id']?.toString())) continue;
      final status = row['status']?.toString();
      if (status == 'void' || status == 'cancelled') continue;
      final net = _netAmount(row['amount'], row['change_amount']);
      totalSales += net;
      totalTickets += 1;
      tickets.add(TicketItem(
        orderId: row['order_id']?.toString() ?? '',
        amount: net,
        createdAt: DateTime.tryParse(row['created_at']?.toString() ?? '') ?? DateTime.now(),
      ));
    }
    tickets.sort((a, b) => b.createdAt.compareTo(a.createdAt));

    final activeOrdersRaw = await _client
        .from('orders')
        .select('id, total, status_ext, created_at, table_sessions!inner(id, business_id, customer_name, dining_tables(code, label)), order_items(product_name, qty, quantity, total)')
        .eq('table_sessions.business_id', businessId)
        .isFilter('closed_at', null)
        .order('created_at', ascending: false)
        .limit(15);

    final liveOrders = <LiveOrderItem>[];
    for (final row in List<Map<String, dynamic>>.from(activeOrdersRaw)) {
      final session = row['table_sessions'];
      final tableData = session is Map<String, dynamic> ? session['dining_tables'] : null;
      final tableLabel = tableData is Map<String, dynamic>
          ? (tableData['label']?.toString() ?? tableData['code']?.toString() ?? 'Mesa')
          : 'Orden';
      final customerName = session is Map<String, dynamic>
          ? session['customer_name']?.toString()
          : null;

      final rawItems = row['order_items'] as List? ?? [];
      final childItems = rawItems.map((ri) => LiveChildItem(
        name: ri['product_name']?.toString() ?? 'Producto',
        quantity: _toDouble(ri['qty'] ?? ri['quantity']),
        total: _toDouble(ri['total']),
      )).toList();

      liveOrders.add(
        LiveOrderItem(
          id: row['id']?.toString() ?? '',
          title: tableLabel,
          subtitle: customerName ?? row['status_ext']?.toString() ?? 'open',
          total: _toDouble(row['total']),
          status: row['status_ext']?.toString() ?? 'open',
          items: childItems,
        ),
      );
    }

    final productsRaw = await _client
        .from('menu_items')
        .select('id, name, price, is_active, categories(name)')
        .eq('business_id', businessId)
        .order('name', ascending: true);

    final catalogItems = List<Map<String, dynamic>>.from(productsRaw)
        .map(
          (row) => CatalogItem(
            name: row['name']?.toString() ?? 'Sin nombre',
            status: (row['is_active'] == true) ? 'Activo' : 'Inactivo',
            price: _toDoubleOrNull(row['price']),
            category: row['categories'] is Map<String, dynamic>
                ? row['categories']['name']?.toString()
                : null,
          ),
        )
        .toList(growable: false);

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

    // --- Hourly sales for today (always today, independent of filter) ---
    final todayStart = DateTime(now.year, now.month, now.day).toUtc().toIso8601String();
    final tomorrowStart = DateTime(now.year, now.month, now.day + 1).toUtc().toIso8601String();

    final todayPaymentsRaw = await _client
        .from('payments')
        .select('amount, change_amount, status, order_id, created_at')
        .gte('created_at', todayStart)
        .lt('created_at', tomorrowStart);

    final todayPayments = List<Map<String, dynamic>>.from(todayPaymentsRaw);

    // Build today-specific scoped order IDs (filter period may not include today).
    final todayOrderIds = todayPayments
        .map((row) => row['order_id']?.toString())
        .whereType<String>()
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList(growable: false);

    final scopedTodayOrderIds = <String>{};
    if (todayOrderIds.isNotEmpty) {
      for (var i = 0; i < todayOrderIds.length; i += _batchSize) {
        final chunk = todayOrderIds.sublist(i, i + _batchSize > todayOrderIds.length ? todayOrderIds.length : i + _batchSize);
        final scoped = await _client
            .from('orders')
            .select('id, table_sessions!inner(business_id)')
            .inFilter('id', chunk)
            .eq('table_sessions.business_id', businessId);
        for (final row in List<Map<String, dynamic>>.from(scoped)) {
          final id = row['id']?.toString();
          if (id != null && id.isNotEmpty) scopedTodayOrderIds.add(id);
        }
      }
    }

    final Map<int, double> hourlyMap = {};
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
    }

    final hourlySales = hourlyMap.entries
        .map((e) => HourlySale(hour: e.key, amount: e.value))
        .toList()
      ..sort((a, b) => a.hour.compareTo(b.hour));

    // --- Comparison sales for previous equivalent period ---
    final pStart = prevStart.toUtc().toIso8601String();
    final pEnd = prevEnd.toUtc().toIso8601String();
    
    final prevPaymentsRaw = await _client
        .from('payments')
        .select('amount, change_amount, status, order_id, created_at')
        .gte('created_at', pStart)
        .lt('created_at', pEnd);

    final prevPaymentRows = List<Map<String, dynamic>>.from(prevPaymentsRaw);
    final prevOrderIds = prevPaymentRows
        .map((row) => row['order_id']?.toString())
        .whereType<String>()
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList(growable: false);

    final scopedPrevOrderIds = <String>{};
    if (prevOrderIds.isNotEmpty) {
      for (var i = 0; i < prevOrderIds.length; i += _batchSize) {
        final chunk = prevOrderIds.sublist(i, i + _batchSize > prevOrderIds.length ? prevOrderIds.length : i + _batchSize);
        final scoped = await _client
            .from('orders')
            .select('id, table_sessions!inner(business_id)')
            .inFilter('id', chunk)
            .eq('table_sessions.business_id', businessId);
        for (final row in List<Map<String, dynamic>>.from(scoped)) {
          final id = row['id']?.toString();
          if (id != null && id.isNotEmpty) scopedPrevOrderIds.add(id);
        }
      }
    }

    double previousDaySales = 0;
    for (final row in prevPaymentRows) {
      if (!scopedPrevOrderIds.contains(row['order_id']?.toString())) continue;
      final status = row['status']?.toString();
      if (status == 'void' || status == 'cancelled') continue;
      previousDaySales += _netAmount(row['amount'], row['change_amount']);
    }

    // --- Pending amount & pending tables ---
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

    // --- Top seller (waiter/cashier with most sales today) ---
    TopSeller? topSeller;
    if (scopedOrderIds.isNotEmpty) {
      // NOTE: order_items doesn't have a 'created_by' column according to the database.
      // Fetching only existing columns to avoid crash.
      final todayOrderItemsRaw = await _batchedInFilter(
        table: 'order_items',
        select: 'order_id, total, status',
        filterColumn: 'order_id',
        values: scopedOrderIds.toList(),
      );

      final Map<String, _SellerAgg> sellerMap = {};
      for (final row in List<Map<String, dynamic>>.from(todayOrderItemsRaw)) {
        if (row['status']?.toString() == 'void') continue;
        
        // TODO: find the correct column for seller name or join with orders/users.
        // For now, this feature is disabled to prevent crashing.
        final createdBy = row['created_by']?.toString();
        if (createdBy == null || createdBy.isEmpty) continue;
        final agg = sellerMap.putIfAbsent(createdBy, () => _SellerAgg());
        agg.total += _toDouble(row['total']);
        agg.orders.add(row['order_id']?.toString() ?? '');
      }

      if (sellerMap.isNotEmpty) {
        final best = sellerMap.entries.reduce((a, b) => a.value.total >= b.value.total ? a : b);
        topSeller = TopSeller(
          name: best.key,
          totalSales: best.value.total,
          orderCount: best.value.orders.length,
        );
      }
    }

    return DashboardSummary(
      profile: profile,
      totalSales: totalSales,
      totalTickets: totalTickets,
      averageTicket: totalTickets == 0 ? 0 : totalSales / totalTickets,
      activeOrders: liveOrders.length,
      topProducts: topProducts.take(5).toList(growable: false),
      catalogItems: catalogItems.take(10).toList(growable: false),
      liveOrders: liveOrders,
      pendingAmount: pendingAmount,
      previousDaySales: previousDaySales,
      hourlySales: hourlySales,
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
}

class _SellerAgg {
  double total = 0;
  final Set<String> orders = {};
}
