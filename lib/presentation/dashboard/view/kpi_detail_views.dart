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
                style: TextStyle(
                  fontSize: dpi.font(15),
                  fontWeight: FontWeight.w800,
                  color: MangoThemeFactory.textColor(context),
                ),
              ),
            ],
          ),
          if (order.items.isNotEmpty) ...[
            SizedBox(height: dpi.space(12)),
            ...order.items.take(4).map(
              (item) => Padding(
                padding: EdgeInsets.only(bottom: dpi.space(6)),
                child: Row(
                  children: [
                    Expanded(child: Text(item.name, style: Theme.of(context).textTheme.bodySmall)),
                    Text('${item.quantity.toStringAsFixed(0)}x', style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class PendingDetailView extends StatelessWidget {
  const PendingDetailView({super.key, required this.summary});

  final DashboardSummary summary;

  @override
  Widget build(BuildContext context) {
    final dpi = DpiScale.of(context);
    final tables = summary.pendingTables;

    return Scaffold(
      appBar: AppBar(title: const Text('Pendiente por cobrar')),
      body: tables.isEmpty
          ? Center(child: Text('No hay mesas pendientes.', style: Theme.of(context).textTheme.bodySmall))
          : ListView(
              padding: EdgeInsets.all(dpi.space(16)),
              children: [
                Container(
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
                            Text(
                              MangoFormatters.currency(summary.pendingAmount),
                              style: TextStyle(color: Colors.white, fontSize: dpi.font(26), fontWeight: FontWeight.w800),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        '${tables.length} mesas',
                        style: TextStyle(color: Colors.white, fontSize: dpi.font(14), fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                ),
                ...tables.map((table) => _PendingTableCard(table: table)),
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
            width: dpi.scale(38),
            height: dpi.scale(38),
            decoration: BoxDecoration(
              color: MangoThemeFactory.warning.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(dpi.radius(10)),
            ),
            child: Icon(Icons.table_restaurant_rounded, color: MangoThemeFactory.warning, size: dpi.icon(18)),
          ),
          SizedBox(width: dpi.space(12)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(table.tableName, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                SizedBox(height: dpi.space(2)),
                Text(
                  '${table.customerName} · ${table.itemCount} items',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          Text(
            MangoFormatters.currency(table.total),
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

class AverageTicketDetailView extends StatelessWidget {
  const AverageTicketDetailView({super.key, required this.summary});

  final DashboardSummary summary;

  @override
  Widget build(BuildContext context) {
    final dpi = DpiScale.of(context);
    final avg = summary.averageTicket;
    final sales = summary.totalSales;
    final tickets = summary.totalTickets;

    return Scaffold(
      appBar: AppBar(title: const Text('Ticket Promedio')),
      body: ListView(
        padding: EdgeInsets.all(dpi.space(16)),
        children: [
          Container(
            margin: EdgeInsets.only(bottom: dpi.space(16)),
            padding: EdgeInsets.all(dpi.space(18)),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [MangoThemeFactory.info, MangoThemeFactory.info.withValues(alpha: 0.8)],
              ),
              borderRadius: BorderRadius.circular(dpi.radius(20)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Promedio por ticket', style: TextStyle(color: Colors.white70, fontSize: dpi.font(12))),
                SizedBox(height: dpi.space(4)),
                Text(
                  MangoFormatters.currency(avg),
                  style: TextStyle(color: Colors.white, fontSize: dpi.font(28), fontWeight: FontWeight.w800),
                ),
              ],
            ),
          ),
          _MetricCard(
            icon: Icons.trending_up_rounded,
            color: MangoThemeFactory.info,
            label: 'Ventas totales',
            value: MangoFormatters.currency(sales),
          ),
          SizedBox(height: dpi.space(10)),
          _MetricCard(
            icon: Icons.receipt_long_rounded,
            color: MangoThemeFactory.mango,
            label: 'Tickets emitidos',
            value: '$tickets',
          ),
          SizedBox(height: dpi.space(16)),
          Container(
            padding: EdgeInsets.all(dpi.space(16)),
            decoration: BoxDecoration(
              color: MangoThemeFactory.cardColor(context),
              borderRadius: BorderRadius.circular(dpi.radius(16)),
              border: Border.all(color: MangoThemeFactory.borderColor(context)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Rangos estimados', style: Theme.of(context).textTheme.titleMedium),
                SizedBox(height: dpi.space(12)),
                _RangeBar(label: 'Bajo (< RD\$500)', count: summary.tickets.where((t) => t.amount < 500).length, total: tickets),
                _RangeBar(
                  label: 'Medio (RD\$500 - RD\$1500)',
                  count: summary.tickets.where((t) => t.amount >= 500 && t.amount < 1500).length,
                  total: tickets,
                ),
                _RangeBar(label: 'Alto (> RD\$1500)', count: summary.tickets.where((t) => t.amount >= 1500).length, total: tickets),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class CashRegisterDetailView extends StatelessWidget {
  const CashRegisterDetailView({super.key, this.summary, this.error});

  final CashRegisterSummary? summary;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final dpi = DpiScale.of(context);
    final data = summary;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Cierres de Caja'),
        centerTitle: false,
      ),
      body: error != null
          ? Center(child: Text(error!, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.red)))
          : data == null
          ? Center(child: Text('Cargando cajas...', style: Theme.of(context).textTheme.bodySmall))
          : ListView(
              padding: EdgeInsets.all(dpi.space(16)),
              children: [
                Container(
                  padding: EdgeInsets.all(dpi.space(18)),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [MangoThemeFactory.info, MangoThemeFactory.info.withValues(alpha: 0.8)],
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
                              'Cierres de caja',
                              style: TextStyle(color: Colors.white70, fontSize: dpi.font(12), fontWeight: FontWeight.w500),
                            ),
                            SizedBox(height: dpi.space(4)),
                            Text(
                              '${data.openRegistersCount} abiertas · ${data.closings.length} cierres',
                              style: TextStyle(color: Colors.white, fontSize: dpi.font(24), fontWeight: FontWeight.w800),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        width: dpi.scale(48),
                        height: dpi.scale(48),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(dpi.radius(14)),
                        ),
                        child: Icon(Icons.point_of_sale_rounded, color: Colors.white, size: dpi.icon(24)),
                      ),
                    ],
                  ),
                ),
                SizedBox(height: dpi.space(16)),
                if (data.openRegisters.isNotEmpty) ...[
                  Text('Cajas abiertas', style: Theme.of(context).textTheme.titleMedium),
                  SizedBox(height: dpi.space(10)),
                  ...data.openRegisters.map((session) => _OpenRegisterCard(session: session)),
                  SizedBox(height: dpi.space(18)),
                ],
                if (data.closings.isEmpty)
                  Container(
                    width: double.infinity,
                    padding: EdgeInsets.all(dpi.space(28)),
                    decoration: BoxDecoration(
                      color: MangoThemeFactory.cardColor(context),
                      borderRadius: BorderRadius.circular(dpi.radius(20)),
                      border: Border.all(color: MangoThemeFactory.borderColor(context)),
                    ),
                    child: Column(
                      children: [
                        Container(
                          width: dpi.scale(56),
                          height: dpi.scale(56),
                          decoration: BoxDecoration(
                            color: MangoThemeFactory.mango.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(dpi.radius(16)),
                          ),
                          child: Icon(Icons.inbox_rounded, color: MangoThemeFactory.mango, size: dpi.icon(28)),
                        ),
                        SizedBox(height: dpi.space(14)),
                        Text(
                          'Sin cierres registrados',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        SizedBox(height: dpi.space(6)),
                        Text(
                          'Los cierres de caja aparecerán aquí cuando se registren desde el punto de venta.',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  )
                else ...[
                  Text('Historial de cierres', style: Theme.of(context).textTheme.titleMedium),
                  SizedBox(height: dpi.space(10)),
                  ...data.closings.map((closing) => _ClosingCard(closing: closing)),
                ],
                SizedBox(height: dpi.space(30)),
              ],
            ),
    );
  }
}

class _OpenRegisterCard extends StatelessWidget {
  const _OpenRegisterCard({required this.session});

  final RegisterSession session;

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
            width: dpi.scale(40),
            height: dpi.scale(40),
            decoration: BoxDecoration(
              color: MangoThemeFactory.success.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(dpi.radius(12)),
            ),
            child: Icon(Icons.point_of_sale_rounded, color: MangoThemeFactory.success, size: dpi.icon(20)),
          ),
          SizedBox(width: dpi.space(12)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(session.registerName, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                SizedBox(height: dpi.space(2)),
                Text('Abierta por ${session.openedByName}', style: Theme.of(context).textTheme.bodySmall),
                Text('Apertura: ${MangoFormatters.currency(session.openingAmount)}', style: Theme.of(context).textTheme.bodySmall),
                if (session.deviceName != null && session.deviceName!.trim().isNotEmpty)
                  Text(session.deviceName!, style: Theme.of(context).textTheme.bodySmall),
                SizedBox(height: dpi.space(6)),
                Wrap(
                  spacing: dpi.space(10),
                  runSpacing: dpi.space(4),
                  children: [
                    if (session.cashSales > 0)
                      _PayMethodChip(icon: Icons.payments_rounded, label: MangoFormatters.currency(session.cashSales), color: MangoThemeFactory.success),
                    if (session.cardSales > 0)
                      _PayMethodChip(icon: Icons.credit_card_rounded, label: MangoFormatters.currency(session.cardSales), color: Colors.blueAccent),
                    if (session.transferSales > 0)
                      _PayMethodChip(icon: Icons.swap_horiz_rounded, label: MangoFormatters.currency(session.transferSales), color: Colors.deepPurpleAccent),
                    if (session.otherSales > 0)
                      _PayMethodChip(icon: Icons.more_horiz_rounded, label: MangoFormatters.currency(session.otherSales), color: Colors.grey),
                  ],
                ),
              ],
            ),
          ),
          Text(
            MangoFormatters.currency(session.totalSales),
            style: TextStyle(fontSize: dpi.font(14), fontWeight: FontWeight.w800, color: MangoThemeFactory.textColor(context)),
          ),
        ],
      ),
    );
  }
}

class _ClosingCard extends StatelessWidget {
  const _ClosingCard({required this.closing});

  final RegisterClosing closing;

  @override
  Widget build(BuildContext context) {
    final dpi = DpiScale.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: dpi.space(10)),
      child: InkWell(
        onTap: () => showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (_) => _ClosingDetailSheet(closing: closing),
        ),
        borderRadius: BorderRadius.circular(dpi.radius(16)),
        child: Container(
          padding: EdgeInsets.all(dpi.space(14)),
          decoration: BoxDecoration(
            color: MangoThemeFactory.cardColor(context),
            borderRadius: BorderRadius.circular(dpi.radius(16)),
            border: Border.all(color: MangoThemeFactory.borderColor(context)),
          ),
          child: Row(
            children: [
              Container(
                width: dpi.scale(40),
                height: dpi.scale(40),
                decoration: BoxDecoration(
                  color: MangoThemeFactory.info.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(dpi.radius(12)),
                ),
                child: Icon(Icons.receipt_long_rounded, color: MangoThemeFactory.info, size: dpi.icon(20)),
              ),
              SizedBox(width: dpi.space(12)),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(closing.registerName, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                    SizedBox(height: dpi.space(2)),
                    Text('Cerrada por ${closing.closedByName}', style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    MangoFormatters.currency(closing.totalSales),
                    style: TextStyle(fontSize: dpi.font(14), fontWeight: FontWeight.w800, color: MangoThemeFactory.textColor(context)),
                  ),
                  Text('ventas', style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ClosingDetailSheet extends StatelessWidget {
  const _ClosingDetailSheet({required this.closing});

  final RegisterClosing closing;

  @override
  Widget build(BuildContext context) {
    final dpi = DpiScale.of(context);
    final differenceColor = closing.difference >= 0 ? MangoThemeFactory.success : Colors.redAccent;

    return DraggableScrollableSheet(
      initialChildSize: 0.62,
      minChildSize: 0.45,
      maxChildSize: 0.9,
      builder: (context, controller) {
        return Container(
          decoration: BoxDecoration(
            color: MangoThemeFactory.cardColor(context),
            borderRadius: BorderRadius.vertical(top: Radius.circular(dpi.radius(24))),
          ),
          child: ListView(
            controller: controller,
            padding: EdgeInsets.fromLTRB(dpi.space(18), dpi.space(18), dpi.space(18), dpi.space(18) + MediaQuery.of(context).padding.bottom),
            children: [
              Center(
                child: Container(
                  width: dpi.scale(42),
                  height: dpi.scale(4),
                  decoration: BoxDecoration(
                    color: MangoThemeFactory.borderColor(context),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              SizedBox(height: dpi.space(18)),
              Text(closing.registerName, style: Theme.of(context).textTheme.titleLarge),
              SizedBox(height: dpi.space(4)),
              Text('Cierre realizado por ${closing.closedByName}', style: Theme.of(context).textTheme.bodySmall),
              if (closing.deviceName != null && closing.deviceName!.trim().isNotEmpty) ...[
                SizedBox(height: dpi.space(2)),
                Text('Dispositivo: ${closing.deviceName}', style: Theme.of(context).textTheme.bodySmall),
              ],
              SizedBox(height: dpi.space(18)),
              Text('Cómo abrió', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
              SizedBox(height: dpi.space(10)),
              _MetricCard(icon: Icons.lock_open_rounded, color: MangoThemeFactory.mango, label: 'Monto apertura', value: MangoFormatters.currency(closing.openingAmount)),
              SizedBox(height: dpi.space(18)),
              Text('Qué hubo en la caja', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
              SizedBox(height: dpi.space(10)),
              _MetricCard(icon: Icons.payments_rounded, color: MangoThemeFactory.success, label: 'Ventas totales', value: MangoFormatters.currency(closing.totalSales)),
              SizedBox(height: dpi.space(8)),
              Padding(
                padding: EdgeInsets.only(left: dpi.space(4)),
                child: Wrap(
                  spacing: dpi.space(10),
                  runSpacing: dpi.space(6),
                  children: [
                    if (closing.cashSales > 0)
                      _PayMethodChip(icon: Icons.payments_rounded, label: MangoFormatters.currency(closing.cashSales), color: MangoThemeFactory.success),
                    if (closing.cardSales > 0)
                      _PayMethodChip(icon: Icons.credit_card_rounded, label: MangoFormatters.currency(closing.cardSales), color: Colors.blueAccent),
                    if (closing.transferSales > 0)
                      _PayMethodChip(icon: Icons.swap_horiz_rounded, label: MangoFormatters.currency(closing.transferSales), color: Colors.deepPurpleAccent),
                    if (closing.otherSales > 0)
                      _PayMethodChip(icon: Icons.more_horiz_rounded, label: MangoFormatters.currency(closing.otherSales), color: Colors.grey),
                  ],
                ),
              ),
              SizedBox(height: dpi.space(10)),
              _MetricCard(icon: Icons.add_circle_outline_rounded, color: MangoThemeFactory.info, label: 'Depósitos', value: MangoFormatters.currency(closing.totalDeposits)),
              SizedBox(height: dpi.space(10)),
              _MetricCard(icon: Icons.remove_circle_outline_rounded, color: MangoThemeFactory.warning, label: 'Retiros', value: MangoFormatters.currency(closing.totalWithdrawals)),
              SizedBox(height: dpi.space(10)),
              _MetricCard(icon: Icons.receipt_rounded, color: Colors.redAccent, label: 'Gastos', value: MangoFormatters.currency(closing.totalExpenses)),
              SizedBox(height: dpi.space(18)),
              Text('Cómo cerró', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
              SizedBox(height: dpi.space(10)),
              _MetricCard(icon: Icons.calculate_rounded, color: MangoThemeFactory.info, label: 'Esperado', value: MangoFormatters.currency(closing.expectedAmount)),
              SizedBox(height: dpi.space(10)),
              _MetricCard(icon: Icons.account_balance_wallet_rounded, color: MangoThemeFactory.warning, label: 'Monto cierre', value: MangoFormatters.currency(closing.closingAmount)),
              SizedBox(height: dpi.space(10)),
              _MetricCard(icon: Icons.compare_arrows_rounded, color: differenceColor, label: 'Diferencia', value: MangoFormatters.currency(closing.difference)),
              SizedBox(height: dpi.space(24)),
            ],
          ),
        );
      },
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({required this.icon, required this.color, required this.label, required this.value});
  final IconData icon;
  final Color color;
  final String label;
  final String value;

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
      child: Row(
        children: [
          Container(
            width: dpi.scale(38),
            height: dpi.scale(38),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(dpi.radius(10)),
            ),
            child: Icon(icon, color: color, size: dpi.icon(18)),
          ),
          SizedBox(width: dpi.space(12)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: Theme.of(context).textTheme.bodySmall),
                SizedBox(height: dpi.space(2)),
                Text(value, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
              ],
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
                widthFactor: percent.clamp(0.0, 1.0),
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

class _PayMethodChip extends StatelessWidget {
  const _PayMethodChip({required this.icon, required this.label, required this.color});
  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final dpi = DpiScale.of(context);
    return Container(
      padding: EdgeInsets.symmetric(horizontal: dpi.space(8), vertical: dpi.space(4)),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(dpi.radius(8)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: dpi.icon(14), color: color),
          SizedBox(width: dpi.space(4)),
          Text(label, style: TextStyle(fontSize: dpi.font(11), fontWeight: FontWeight.w700, color: color)),
        ],
      ),
    );
  }
}
