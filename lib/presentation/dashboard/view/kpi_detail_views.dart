import 'package:flutter/material.dart';

import '../../../core/formatters/mango_formatters.dart';
import '../../../core/responsive/dpi_scale.dart';
import '../../../domain/dashboard/dashboard_models.dart';
import '../../theme/theme_data_factory.dart';

/// Ventas del día - lista de todos los tickets/pagos
class SalesDetailView extends StatelessWidget {
  const SalesDetailView({super.key, required this.summary});

  final DashboardSummary summary;

  @override
  Widget build(BuildContext context) {
    final dpi = DpiScale.of(context);
    final tickets = summary.tickets;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Ventas del día'),
        centerTitle: false,
      ),
      body: tickets.isEmpty
          ? Center(
              child: Text('No hay ventas registradas.', style: Theme.of(context).textTheme.bodySmall),
            )
          : ListView.builder(
              padding: EdgeInsets.all(dpi.space(16)),
              itemCount: tickets.length + 1,
              itemBuilder: (context, index) {
                if (index == 0) {
                  return _SalesSummaryHeader(summary: summary);
                }
                final ticket = tickets[index - 1];
                return _TicketCard(ticket: ticket, index: index);
              },
            ),
    );
  }
}

class _SalesSummaryHeader extends StatelessWidget {
  const _SalesSummaryHeader({required this.summary});
  final DashboardSummary summary;

  @override
  Widget build(BuildContext context) {
    final dpi = DpiScale.of(context);
    return Container(
      margin: EdgeInsets.only(bottom: dpi.space(16)),
      padding: EdgeInsets.all(dpi.space(18)),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [MangoThemeFactory.success, Color(0xFF16A34A)],
        ),
        borderRadius: BorderRadius.circular(dpi.radius(20)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Total del día',
                  style: TextStyle(color: Colors.white70, fontSize: dpi.font(12), fontWeight: FontWeight.w500),
                ),
                SizedBox(height: dpi.space(4)),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    MangoFormatters.currency(summary.totalSales),
                    style: TextStyle(color: Colors.white, fontSize: dpi.font(26), fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(width: dpi.space(16)),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${summary.totalTickets}',
                style: TextStyle(color: Colors.white, fontSize: dpi.font(22), fontWeight: FontWeight.w800),
              ),
              Text(
                'tickets',
                style: TextStyle(color: Colors.white70, fontSize: dpi.font(11)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TicketCard extends StatelessWidget {
  const _TicketCard({required this.ticket, required this.index});
  final TicketItem ticket;
  final int index;

  @override
  Widget build(BuildContext context) {
    final dpi = DpiScale.of(context);
    final time = ticket.createdAt.toLocal();
    final hour = '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';

    return Container(
      margin: EdgeInsets.only(bottom: dpi.space(10)),
      padding: EdgeInsets.all(dpi.space(14)),
      decoration: BoxDecoration(
        color: MangoThemeFactory.cardColor(context),
        borderRadius: BorderRadius.circular(dpi.radius(16)),
        border: Border.all(color: MangoThemeFactory.borderColor(context)),
      ),
      child: Row(
        children: [
          Container(
            width: dpi.scale(38),
            height: dpi.scale(38),
            decoration: BoxDecoration(
              color: MangoThemeFactory.success.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(dpi.radius(10)),
            ),
            child: Icon(Icons.receipt_rounded, color: MangoThemeFactory.success, size: dpi.icon(18)),
          ),
          SizedBox(width: dpi.space(12)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Ticket #$index',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
                SizedBox(height: dpi.space(2)),
                Text(hour, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
          Text(
            MangoFormatters.currency(ticket.amount),
            style: TextStyle(
              fontSize: dpi.font(15),
              fontWeight: FontWeight.w800,
              color: MangoThemeFactory.textColor(context),
            ),
          ),
        ],
      ),
    );
  }
}

/// Órdenes - lista de todas las órdenes del período
class OrdersDetailView extends StatelessWidget {
  const OrdersDetailView({super.key, required this.summary});

  final DashboardSummary summary;

  @override
  Widget build(BuildContext context) {
    final dpi = DpiScale.of(context);
    final orders = summary.liveOrders;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Órdenes'),
        centerTitle: false,
      ),
      body: orders.isEmpty
          ? Center(child: Text('No hay órdenes activas.', style: Theme.of(context).textTheme.bodySmall))
          : ListView.builder(
              padding: EdgeInsets.all(dpi.space(16)),
              itemCount: orders.length + 1,
              itemBuilder: (context, index) {
                if (index == 0) {
                  return _OrdersSummaryHeader(
                    total: summary.totalTickets,
                    active: summary.activeOrders,
                  );
                }
                final order = orders[index - 1];
                return _OrderDetailCard(order: order);
              },
            ),
    );
  }
}

class _OrdersSummaryHeader extends StatelessWidget {
  const _OrdersSummaryHeader({required this.total, required this.active});
  final int total;
  final int active;

  @override
  Widget build(BuildContext context) {
    final dpi = DpiScale.of(context);
    return Container(
      margin: EdgeInsets.only(bottom: dpi.space(16)),
      padding: EdgeInsets.all(dpi.space(18)),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [MangoThemeFactory.mango, MangoThemeFactory.mango.withValues(alpha: 0.8)],
        ),
        borderRadius: BorderRadius.circular(dpi.radius(20)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Total órdenes', style: TextStyle(color: Colors.white70, fontSize: dpi.font(12))),
                SizedBox(height: dpi.space(4)),
                Text('$total', style: TextStyle(color: Colors.white, fontSize: dpi.font(26), fontWeight: FontWeight.w800)),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('$active', style: TextStyle(color: Colors.white, fontSize: dpi.font(22), fontWeight: FontWeight.w800)),
              Text('activas', style: TextStyle(color: Colors.white70, fontSize: dpi.font(11))),
            ],
          ),
        ],
      ),
    );
  }
}

class _OrderDetailCard extends StatelessWidget {
  const _OrderDetailCard({required this.order});
  final LiveOrderItem order;

  @override
  Widget build(BuildContext context) {
    final dpi = DpiScale.of(context);
    return Container(
      margin: EdgeInsets.only(bottom: dpi.space(10)),
      padding: EdgeInsets.all(dpi.space(14)),
      decoration: BoxDecoration(
        color: MangoThemeFactory.cardColor(context),
        borderRadius: BorderRadius.circular(dpi.radius(16)),
        border: Border.all(color: MangoThemeFactory.borderColor(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: dpi.scale(38),
                height: dpi.scale(38),
                decoration: BoxDecoration(
                  color: MangoThemeFactory.mango.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(dpi.radius(10)),
                ),
                child: Icon(Icons.restaurant_rounded, color: MangoThemeFactory.mango, size: dpi.icon(18)),
              ),
              SizedBox(width: dpi.space(12)),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(order.title, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                    SizedBox(height: dpi.space(2)),
                    Text(order.subtitle, style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ),
              Text(
                MangoFormatters.currency(order.total),
                style: TextStyle(fontSize: dpi.font(15), fontWeight: FontWeight.w800, color: MangoThemeFactory.textColor(context)),
              ),
            ],
          ),
          if (order.items.isNotEmpty) ...[
            SizedBox(height: dpi.space(10)),
            Divider(color: MangoThemeFactory.borderColor(context)),
            SizedBox(height: dpi.space(6)),
            ...order.items.map((item) => Padding(
                  padding: EdgeInsets.only(bottom: dpi.space(4)),
                  child: Row(
                    children: [
                      Text(
                        '${item.quantity.toStringAsFixed(0)}x',
                        style: TextStyle(fontSize: dpi.font(12), fontWeight: FontWeight.w700, color: MangoThemeFactory.mango),
                      ),
                      SizedBox(width: dpi.space(8)),
                      Expanded(child: Text(item.name, style: Theme.of(context).textTheme.bodySmall)),
                      Text(MangoFormatters.currency(item.total), style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
                )),
          ],
        ],
      ),
    );
  }
}

/// Por Cobrar - mesas abiertas con nombre del cliente
class PendingDetailView extends StatelessWidget {
  const PendingDetailView({super.key, required this.summary});

  final DashboardSummary summary;

  @override
  Widget build(BuildContext context) {
    final dpi = DpiScale.of(context);
    final tables = summary.pendingTables;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Por cobrar'),
        centerTitle: false,
      ),
      body: tables.isEmpty
          ? Center(child: Text('No hay mesas abiertas.', style: Theme.of(context).textTheme.bodySmall))
          : ListView.builder(
              padding: EdgeInsets.all(dpi.space(16)),
              itemCount: tables.length + 1,
              itemBuilder: (context, index) {
                if (index == 0) {
                  return _PendingSummaryHeader(
                    total: summary.pendingAmount,
                    count: tables.length,
                  );
                }
                return _PendingTableCard(table: tables[index - 1]);
              },
            ),
    );
  }
}

class _PendingSummaryHeader extends StatelessWidget {
  const _PendingSummaryHeader({required this.total, required this.count});
  final double total;
  final int count;

  @override
  Widget build(BuildContext context) {
    final dpi = DpiScale.of(context);
    return Container(
      margin: EdgeInsets.only(bottom: dpi.space(16)),
      padding: EdgeInsets.all(dpi.space(18)),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [MangoThemeFactory.warning, MangoThemeFactory.warning.withValues(alpha: 0.8)],
        ),
        borderRadius: BorderRadius.circular(dpi.radius(20)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Pendiente total', style: TextStyle(color: Colors.white70, fontSize: dpi.font(12))),
                SizedBox(height: dpi.space(4)),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    MangoFormatters.currency(total),
                    style: TextStyle(color: Colors.white, fontSize: dpi.font(26), fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('$count', style: TextStyle(color: Colors.white, fontSize: dpi.font(22), fontWeight: FontWeight.w800)),
              Text('mesas', style: TextStyle(color: Colors.white70, fontSize: dpi.font(11))),
            ],
          ),
        ],
      ),
    );
  }
}

class _PendingTableCard extends StatelessWidget {
  const _PendingTableCard({required this.table});
  final PendingTable table;

  @override
  Widget build(BuildContext context) {
    final dpi = DpiScale.of(context);
    return Container(
      margin: EdgeInsets.only(bottom: dpi.space(10)),
      padding: EdgeInsets.all(dpi.space(14)),
      decoration: BoxDecoration(
        color: MangoThemeFactory.cardColor(context),
        borderRadius: BorderRadius.circular(dpi.radius(16)),
        border: Border.all(color: MangoThemeFactory.borderColor(context)),
      ),
      child: Row(
        children: [
          Container(
            width: dpi.scale(42),
            height: dpi.scale(42),
            decoration: BoxDecoration(
              color: MangoThemeFactory.warning.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(dpi.radius(12)),
            ),
            child: Icon(Icons.table_restaurant_rounded, color: MangoThemeFactory.warning, size: dpi.icon(20)),
          ),
          SizedBox(width: dpi.space(12)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  table.tableName,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
                SizedBox(height: dpi.space(2)),
                Text(
                  table.customerName.isNotEmpty ? table.customerName : 'Sin nombre',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                SizedBox(height: dpi.space(2)),
                Text(
                  '${table.itemCount} productos',
                  style: TextStyle(fontSize: dpi.font(11), color: MangoThemeFactory.mutedText(context)),
                ),
              ],
            ),
          ),
          Text(
            MangoFormatters.currency(table.total),
            style: TextStyle(
              fontSize: dpi.font(16),
              fontWeight: FontWeight.w800,
              color: MangoThemeFactory.warning,
            ),
          ),
        ],
      ),
    );
  }
}

/// Ticket Promedio - desglose y distribución
class AverageTicketDetailView extends StatelessWidget {
  const AverageTicketDetailView({super.key, required this.summary});

  final DashboardSummary summary;

  @override
  Widget build(BuildContext context) {
    final dpi = DpiScale.of(context);
    final tickets = summary.tickets;

    // Calcular distribución por rangos
    final ranges = <String, int>{};
    for (final t in tickets) {
      final label = _rangeLabel(t.amount);
      ranges[label] = (ranges[label] ?? 0) + 1;
    }
    final sortedRanges = ranges.entries.toList()..sort((a, b) => b.value.compareTo(a.value));

    // Ticket más alto y más bajo
    double maxTicket = 0;
    double minTicket = double.infinity;
    for (final t in tickets) {
      if (t.amount > maxTicket) maxTicket = t.amount;
      if (t.amount < minTicket) minTicket = t.amount;
    }
    if (tickets.isEmpty) minTicket = 0;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Ticket promedio'),
        centerTitle: false,
      ),
      body: ListView(
        padding: EdgeInsets.all(dpi.space(16)),
        children: [
          // Header
          Container(
            padding: EdgeInsets.all(dpi.space(18)),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [MangoThemeFactory.info, MangoThemeFactory.info.withValues(alpha: 0.8)],
              ),
              borderRadius: BorderRadius.circular(dpi.radius(20)),
            ),
            child: Column(
              children: [
                Text('Ticket promedio', style: TextStyle(color: Colors.white70, fontSize: dpi.font(12))),
                SizedBox(height: dpi.space(6)),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    MangoFormatters.currency(summary.averageTicket),
                    style: TextStyle(color: Colors.white, fontSize: dpi.font(32), fontWeight: FontWeight.w800),
                  ),
                ),
                SizedBox(height: dpi.space(4)),
                Text(
                  'Basado en ${summary.totalTickets} tickets',
                  style: TextStyle(color: Colors.white70, fontSize: dpi.font(12)),
                ),
              ],
            ),
          ),
          SizedBox(height: dpi.space(20)),

          // Min / Max
          Row(
            children: [
              Expanded(
                child: _StatCard(
                  label: 'Ticket más bajo',
                  value: MangoFormatters.currency(minTicket),
                  icon: Icons.arrow_downward_rounded,
                  color: MangoThemeFactory.danger,
                ),
              ),
              SizedBox(width: dpi.space(10)),
              Expanded(
                child: _StatCard(
                  label: 'Ticket más alto',
                  value: MangoFormatters.currency(maxTicket),
                  icon: Icons.arrow_upward_rounded,
                  color: MangoThemeFactory.success,
                ),
              ),
            ],
          ),
          SizedBox(height: dpi.space(20)),

          // Distribución
          Text('Distribución por rango', style: Theme.of(context).textTheme.titleMedium),
          SizedBox(height: dpi.space(12)),
          if (sortedRanges.isEmpty)
            Text('Sin datos suficientes.', style: Theme.of(context).textTheme.bodySmall)
          else
            ...sortedRanges.map((e) => _RangeBar(
                  label: e.key,
                  count: e.value,
                  total: tickets.length,
                )),
          SizedBox(height: dpi.space(30)),
        ],
      ),
    );
  }

  String _rangeLabel(double amount) {
    if (amount < 200) return 'RD\$ 0 - 199';
    if (amount < 500) return 'RD\$ 200 - 499';
    if (amount < 1000) return 'RD\$ 500 - 999';
    if (amount < 2000) return 'RD\$ 1,000 - 1,999';
    if (amount < 5000) return 'RD\$ 2,000 - 4,999';
    return 'RD\$ 5,000+';
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({required this.label, required this.value, required this.icon, required this.color});
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final dpi = DpiScale.of(context);
    return Container(
      padding: EdgeInsets.all(dpi.space(14)),
      decoration: BoxDecoration(
        color: MangoThemeFactory.cardColor(context),
        borderRadius: BorderRadius.circular(dpi.radius(16)),
        border: Border.all(color: MangoThemeFactory.borderColor(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: dpi.icon(20)),
          SizedBox(height: dpi.space(8)),
          Text(label, style: Theme.of(context).textTheme.bodySmall),
          SizedBox(height: dpi.space(4)),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: TextStyle(fontSize: dpi.font(17), fontWeight: FontWeight.w800, color: MangoThemeFactory.textColor(context)),
            ),
          ),
        ],
      ),
    );
  }
}

class _RangeBar extends StatelessWidget {
  const _RangeBar({required this.label, required this.count, required this.total});
  final String label;
  final int count;
  final int total;

  @override
  Widget build(BuildContext context) {
    final dpi = DpiScale.of(context);
    final percent = total > 0 ? count / total : 0.0;

    return Padding(
      padding: EdgeInsets.only(bottom: dpi.space(10)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label, style: Theme.of(context).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
              Text('$count tickets', style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
          SizedBox(height: dpi.space(4)),
          Stack(
            children: [
              Container(
                height: dpi.space(8),
                width: double.infinity,
                decoration: BoxDecoration(
                  color: MangoThemeFactory.borderColor(context),
                  borderRadius: BorderRadius.circular(dpi.radius(4)),
                ),
              ),
              FractionallySizedBox(
                widthFactor: percent.clamp(0, 1),
                child: Container(
                  height: dpi.space(8),
                  decoration: BoxDecoration(
                    color: MangoThemeFactory.info,
                    borderRadius: BorderRadius.circular(dpi.radius(4)),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
