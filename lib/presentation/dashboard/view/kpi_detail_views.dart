import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:printing/printing.dart';

import '../../../app/di/providers.dart';
import '../../../core/formatters/mango_formatters.dart';
import '../../../core/responsive/dpi_scale.dart';
import '../../../data/cash_register/reporte_z_pdf_builder.dart';
import '../../../domain/dashboard/dashboard_models.dart';
import '../../auth/viewmodel/auth_gate_view_model.dart';
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
              padding: EdgeInsets.fromLTRB(dpi.space(16), dpi.space(16), dpi.space(16), dpi.space(16) + MediaQuery.of(context).padding.bottom),
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

  static const _methodIcons = <String, IconData>{
    'cash': Icons.payments_rounded,
    'card': Icons.credit_card_rounded,
    'transfer': Icons.swap_horiz_rounded,
  };
  static const _methodColors = <String, Color>{
    'cash': MangoThemeFactory.success,
    'card': Colors.blueAccent,
    'transfer': Colors.deepPurpleAccent,
  };
  static const _methodLabels = <String, String>{
    'cash': 'Efectivo',
    'card': 'Tarjeta',
    'transfer': 'Transferencia',
  };

  @override
  Widget build(BuildContext context) {
    final dpi = DpiScale.of(context);
    final time = ticket.createdAt.toLocal();
    final hour = '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
    final pmCode = ticket.paymentMethodCode;
    final pmColor = _methodColors[pmCode] ?? MangoThemeFactory.success;
    final pmIcon = _methodIcons[pmCode] ?? Icons.receipt_rounded;

    // Build subtitle parts
    final parts = <String>[hour];
    if (ticket.tableName != null && ticket.tableName!.trim().isNotEmpty) {
      parts.add(ticket.tableName!.trim());
    }
    if (ticket.customerName != null && ticket.customerName!.trim().isNotEmpty) {
      parts.add(ticket.customerName!.trim());
    }

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
              color: pmColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(dpi.radius(10)),
            ),
            child: Icon(pmIcon, color: pmColor, size: dpi.icon(18)),
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
                Text(parts.join(' · '), style: Theme.of(context).textTheme.bodySmall),
                if (pmCode != null) ...[
                  SizedBox(height: dpi.space(2)),
                  Text(
                    _methodLabels[pmCode] ?? 'Otro',
                    style: TextStyle(fontSize: dpi.font(10), fontWeight: FontWeight.w600, color: pmColor),
                  ),
                ],
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
class OrdersDetailView extends StatefulWidget {
  const OrdersDetailView({super.key, required this.summary});

  final DashboardSummary summary;

  @override
  State<OrdersDetailView> createState() => _OrdersDetailViewState();
}

class _OrdersDetailViewState extends State<OrdersDetailView> {
  int _filterIndex = 0; // 0: Todas, 1: Activas, 2: Cerradas

  @override
  Widget build(BuildContext context) {
    final dpi = DpiScale.of(context);

    final List<LiveOrderItem> displayedOrders;
    if (_filterIndex == 0) {
      displayedOrders = [...widget.summary.liveOrders, ...widget.summary.closedOrders];
    } else if (_filterIndex == 1) {
      displayedOrders = widget.summary.liveOrders;
    } else {
      displayedOrders = widget.summary.closedOrders;
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Órdenes'),
        centerTitle: false,
      ),
      body: Column(
        children: [
          Padding(
            padding: EdgeInsets.symmetric(horizontal: dpi.space(16), vertical: dpi.space(8)),
            child: _OrderFilterTabs(
              selectedIndex: _filterIndex,
              onChanged: (index) => setState(() => _filterIndex = index),
            ),
          ),
          Expanded(
            child: displayedOrders.isEmpty
                ? Center(
                    child: Text(
                      _filterIndex == 1 ? 'No hay órdenes activas.' : (_filterIndex == 2 ? 'No hay órdenes cerradas.' : 'No hay órdenes registradas.'),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  )
                : ListView.builder(
                    padding: EdgeInsets.fromLTRB(dpi.space(16), dpi.space(10), dpi.space(16), dpi.space(16) + MediaQuery.of(context).padding.bottom),
                    itemCount: displayedOrders.length + (_filterIndex == 0 ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (_filterIndex == 0 && index == 0) {
                        return _OrdersSummaryHeader(
                          total: widget.summary.totalTickets,
                          active: widget.summary.activeOrders,
                        );
                      }
                      
                      final orderIndex = _filterIndex == 0 ? index - 1 : index;
                      final order = displayedOrders[orderIndex];

                      // Section headers if "Todas" is selected
                      if (_filterIndex == 0) {
                         if (orderIndex == 0 && widget.summary.liveOrders.isNotEmpty) {
                           return Column(
                             crossAxisAlignment: CrossAxisAlignment.start,
                             children: [
                               _SectionHeader(title: 'ACTIVAS', count: widget.summary.liveOrders.length, color: MangoThemeFactory.mango),
                               _OrderDetailCard(order: order),
                             ],
                           );
                         }
                         if (orderIndex == widget.summary.liveOrders.length && widget.summary.closedOrders.isNotEmpty) {
                           return Column(
                             crossAxisAlignment: CrossAxisAlignment.start,
                             children: [
                               SizedBox(height: dpi.space(16)),
                               _SectionHeader(title: 'CERRADAS', count: widget.summary.closedOrders.length, color: Colors.grey),
                               _OrderDetailCard(order: order),
                             ],
                           );
                         }
                      }

                      return _OrderDetailCard(order: order);
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.count, required this.color});
  final String title;
  final int count;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final dpi = DpiScale.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: dpi.space(10), left: dpi.space(4)),
      child: Row(
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: dpi.font(11),
              fontWeight: FontWeight.w800,
              color: color,
              letterSpacing: 1.2,
            ),
          ),
          SizedBox(width: dpi.space(8)),
          Container(
            padding: EdgeInsets.symmetric(horizontal: dpi.space(6), vertical: dpi.space(2)),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(dpi.radius(6)),
            ),
            child: Text(
              '$count',
              style: TextStyle(fontSize: dpi.font(10), fontWeight: FontWeight.w700, color: color),
            ),
          ),
        ],
      ),
    );
  }
}

class _OrderFilterTabs extends StatelessWidget {
  const _OrderFilterTabs({required this.selectedIndex, required this.onChanged});
  final int selectedIndex;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final dpi = DpiScale.of(context);
    return Container(
      height: dpi.scale(38),
      padding: EdgeInsets.all(dpi.space(4)),
      decoration: BoxDecoration(
        color: MangoThemeFactory.cardColor(context),
        borderRadius: BorderRadius.circular(dpi.radius(10)),
        border: Border.all(color: MangoThemeFactory.borderColor(context)),
      ),
      child: Row(
        children: [
          _TabItem(label: 'Todas', isSelected: selectedIndex == 0, onTap: () => onChanged(0)),
          _TabItem(label: 'Activas', isSelected: selectedIndex == 1, onTap: () => onChanged(1)),
          _TabItem(label: 'Cerradas', isSelected: selectedIndex == 2, onTap: () => onChanged(2)),
        ],
      ),
    );
  }
}

class _TabItem extends StatelessWidget {
  const _TabItem({required this.label, required this.isSelected, required this.onTap});
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final dpi = DpiScale.of(context);
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isSelected ? MangoThemeFactory.mango : Colors.transparent,
            borderRadius: BorderRadius.circular(dpi.radius(7)),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: dpi.font(12),
              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
              color: isSelected ? Colors.white : MangoThemeFactory.textColor(context).withValues(alpha: 0.6),
            ),
          ),
        ),
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
                  color: (order.status == 'closed' || order.status == 'completed') 
                    ? Colors.grey.withValues(alpha: 0.1)
                    : MangoThemeFactory.mango.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(dpi.radius(10)),
                ),
                child: Icon(
                  (order.status == 'closed' || order.status == 'completed') 
                    ? Icons.check_circle_outline_rounded 
                    : Icons.restaurant_rounded, 
                  color: (order.status == 'closed' || order.status == 'completed')
                    ? Colors.grey
                    : MangoThemeFactory.mango, 
                  size: dpi.icon(18)
                ),
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
              padding: EdgeInsets.fromLTRB(dpi.space(16), dpi.space(16), dpi.space(16), dpi.space(16) + MediaQuery.of(context).padding.bottom),
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
        padding: EdgeInsets.fromLTRB(dpi.space(16), dpi.space(16), dpi.space(16), dpi.space(16) + MediaQuery.of(context).padding.bottom),
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
              padding: EdgeInsets.fromLTRB(dpi.space(16), dpi.space(16), dpi.space(16), dpi.space(16) + MediaQuery.of(context).padding.bottom),
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
                    Text('Cerrada por ${closing.closedByName} · ${MangoFormatters.fullDate(closing.closedAt)}', style: Theme.of(context).textTheme.bodySmall),
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
              Text('Cierre realizado por ${closing.closedByName} · ${MangoFormatters.dateTime(closing.closedAt)}', style: Theme.of(context).textTheme.bodySmall),
              if (closing.deviceName != null && closing.deviceName!.trim().isNotEmpty) ...[
                SizedBox(height: dpi.space(2)),
                Text('Dispositivo: ${closing.deviceName}', style: Theme.of(context).textTheme.bodySmall),
              ],
              SizedBox(height: dpi.space(14)),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () {
                    Navigator.of(context).pop();
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => ReporteZView(closing: closing)),
                    );
                  },
                  icon: const Icon(Icons.receipt_long_rounded),
                  label: const Text('Ver reporte de cierre'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: MangoThemeFactory.mango,
                    side: BorderSide(color: MangoThemeFactory.mango.withValues(alpha: 0.5)),
                    padding: EdgeInsets.symmetric(vertical: dpi.space(12)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(dpi.radius(12))),
                  ),
                ),
              ),
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
              _MetricCard(
                icon: Icons.calculate_rounded,
                color: MangoThemeFactory.info,
                label: 'Esperado en caja',
                value: MangoFormatters.currency(_cashExpected(closing)),
              ),
              SizedBox(height: dpi.space(10)),
              _MetricCard(
                icon: Icons.account_balance_wallet_rounded,
                color: MangoThemeFactory.warning,
                label: 'Contado al cierre',
                value: MangoFormatters.currency(closing.closingAmount),
              ),
              SizedBox(height: dpi.space(10)),
              Builder(
                builder: (_) {
                  final diff = closing.closingAmount - _cashExpected(closing);
                  final isSurplus = diff > 0;
                  final isShortfall = diff < 0;
                  final color = isShortfall
                      ? MangoThemeFactory.danger
                      : (isSurplus ? MangoThemeFactory.success : MangoThemeFactory.mutedText(context));
                  final label = isShortfall ? 'Faltante' : (isSurplus ? 'Sobrante' : 'Diferencia');
                  return _MetricCard(
                    icon: Icons.compare_arrows_rounded,
                    color: color,
                    label: label,
                    value: MangoFormatters.currency(diff.abs()),
                  );
                },
              ),
              SizedBox(height: dpi.space(24)),
            ],
          ),
        );
      },
    );
  }

  /// Expected cash in the drawer at closing time:
  /// `apertura + ventas en efectivo + depósitos − retiros − gastos`.
  /// Mirrors the formula used in the printed receipt.
  static double _cashExpected(RegisterClosing c) {
    return c.openingAmount +
        c.cashSales +
        c.totalDeposits -
        c.totalWithdrawals -
        c.totalExpenses;
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

/// Lista completa de productos vendidos en el periodo seleccionado.
class TopProductsDetailView extends StatefulWidget {
  const TopProductsDetailView({super.key, required this.summary});

  final DashboardSummary summary;

  @override
  State<TopProductsDetailView> createState() => _TopProductsDetailViewState();
}

class _TopProductsDetailViewState extends State<TopProductsDetailView> {
  String _query = '';
  _SortMode _sort = _SortMode.amount;

  @override
  Widget build(BuildContext context) {
    final dpi = DpiScale.of(context);
    final products = widget.summary.topProducts;

    final q = _query.trim().toLowerCase();
    final filtered = q.isEmpty
        ? List<TopProduct>.from(products)
        : products.where((p) => p.label.toLowerCase().contains(q)).toList();

    switch (_sort) {
      case _SortMode.amount:
        filtered.sort((a, b) => b.amount.compareTo(a.amount));
        break;
      case _SortMode.quantity:
        filtered.sort((a, b) => b.quantity.compareTo(a.quantity));
        break;
      case _SortMode.name:
        filtered.sort((a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()));
        break;
    }

    final maxAmount = products.isEmpty ? 0.0 : products.map((p) => p.amount).reduce((a, b) => a > b ? a : b);
    final totalAmount = products.fold<double>(0, (sum, p) => sum + p.amount);
    final totalUnits = products.fold<double>(0, (sum, p) => sum + p.quantity);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Todos los productos'),
        centerTitle: false,
      ),
      body: Column(
        children: [
          _TopProductsHeader(
            totalProducts: products.length,
            totalAmount: totalAmount,
            totalUnits: totalUnits,
            filterLabel: _filterLabel(widget.summary),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(dpi.space(16), 0, dpi.space(16), dpi.space(8)),
            child: TextField(
              onChanged: (v) => setState(() => _query = v),
              decoration: InputDecoration(
                hintText: 'Buscar producto…',
                prefixIcon: const Icon(Icons.search_rounded),
                isDense: true,
                contentPadding: EdgeInsets.symmetric(horizontal: dpi.space(12), vertical: dpi.space(12)),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(dpi.radius(12))),
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(dpi.space(16), 0, dpi.space(16), dpi.space(8)),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _SortChip(
                    label: 'Por monto',
                    selected: _sort == _SortMode.amount,
                    onTap: () => setState(() => _sort = _SortMode.amount),
                  ),
                  SizedBox(width: dpi.space(8)),
                  _SortChip(
                    label: 'Por unidades',
                    selected: _sort == _SortMode.quantity,
                    onTap: () => setState(() => _sort = _SortMode.quantity),
                  ),
                  SizedBox(width: dpi.space(8)),
                  _SortChip(
                    label: 'A-Z',
                    selected: _sort == _SortMode.name,
                    onTap: () => setState(() => _sort = _SortMode.name),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: filtered.isEmpty
                ? Center(
                    child: Text(
                      q.isEmpty ? 'Sin productos en este periodo.' : 'Sin resultados para "$_query".',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  )
                : ListView.separated(
                    padding: EdgeInsets.fromLTRB(dpi.space(16), dpi.space(8), dpi.space(16), dpi.space(16) + MediaQuery.of(context).padding.bottom),
                    itemCount: filtered.length,
                    separatorBuilder: (_, _) => SizedBox(height: dpi.space(10)),
                    itemBuilder: (context, index) {
                      final p = filtered[index];
                      return _TopProductCard(
                        product: p,
                        rank: products.indexOf(p) + 1,
                        maxAmount: maxAmount,
                        totalAmount: totalAmount,
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  static String _filterLabel(DashboardSummary s) {
    switch (s.filter) {
      case SalesDateFilter.today: return 'Hoy';
      case SalesDateFilter.yesterday: return 'Ayer';
      case SalesDateFilter.week: return '7 días';
      case SalesDateFilter.month: return 'Mes';
      case SalesDateFilter.lastMonth: return 'Mes Pasado';
      case SalesDateFilter.last3Months: return '90 días';
      case SalesDateFilter.custom:
        final r = s.customRange;
        if (r == null) return 'Personalizado';
        return '${r.start.day}/${r.start.month} - ${r.end.day}/${r.end.month}';
    }
  }
}

enum _SortMode { amount, quantity, name }

class _TopProductsHeader extends StatelessWidget {
  const _TopProductsHeader({
    required this.totalProducts,
    required this.totalAmount,
    required this.totalUnits,
    required this.filterLabel,
  });

  final int totalProducts;
  final double totalAmount;
  final double totalUnits;
  final String filterLabel;

  @override
  Widget build(BuildContext context) {
    final dpi = DpiScale.of(context);
    return Container(
      margin: EdgeInsets.fromLTRB(dpi.space(16), dpi.space(16), dpi.space(16), dpi.space(12)),
      padding: EdgeInsets.all(dpi.space(18)),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [MangoThemeFactory.mango, MangoThemeFactory.mango.withValues(alpha: 0.78)],
        ),
        borderRadius: BorderRadius.circular(dpi.radius(20)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.local_fire_department_rounded, color: Colors.white, size: dpi.icon(18)),
              SizedBox(width: dpi.space(6)),
              Text(
                filterLabel,
                style: TextStyle(color: Colors.white, fontSize: dpi.font(12), fontWeight: FontWeight.w600),
              ),
            ],
          ),
          SizedBox(height: dpi.space(10)),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Total vendido', style: TextStyle(color: Colors.white70, fontSize: dpi.font(11))),
                    SizedBox(height: dpi.space(2)),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        MangoFormatters.currency(totalAmount),
                        style: TextStyle(color: Colors.white, fontSize: dpi.font(22), fontWeight: FontWeight.w800),
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(width: dpi.space(12)),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('$totalProducts', style: TextStyle(color: Colors.white, fontSize: dpi.font(20), fontWeight: FontWeight.w800)),
                  Text('productos', style: TextStyle(color: Colors.white70, fontSize: dpi.font(11))),
                  SizedBox(height: dpi.space(4)),
                  Text(
                    '${MangoFormatters.number(totalUnits.round())} uds',
                    style: TextStyle(color: Colors.white, fontSize: dpi.font(12), fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SortChip extends StatelessWidget {
  const _SortChip({required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final dpi = DpiScale.of(context);
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
      selectedColor: MangoThemeFactory.mango.withValues(alpha: 0.2),
      labelStyle: TextStyle(
        color: selected ? MangoThemeFactory.mango : null,
        fontWeight: selected ? FontWeight.w700 : null,
        fontSize: dpi.font(12),
      ),
    );
  }
}

class _TopProductCard extends StatelessWidget {
  const _TopProductCard({
    required this.product,
    required this.rank,
    required this.maxAmount,
    required this.totalAmount,
  });

  final TopProduct product;
  final int rank;
  final double maxAmount;
  final double totalAmount;

  @override
  Widget build(BuildContext context) {
    final dpi = DpiScale.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final percent = maxAmount == 0 ? 0.0 : (product.amount / maxAmount);
    final share = totalAmount == 0 ? 0.0 : (product.amount / totalAmount) * 100;

    final rankColor = rank == 1
        ? MangoThemeFactory.mango
        : rank == 2
            ? MangoThemeFactory.warning
            : rank == 3
                ? MangoThemeFactory.info
                : MangoThemeFactory.mutedText(context);

    return Container(
      padding: EdgeInsets.all(dpi.space(14)),
      decoration: BoxDecoration(
        color: MangoThemeFactory.cardColor(context),
        borderRadius: BorderRadius.circular(dpi.radius(14)),
        border: Border.all(color: MangoThemeFactory.borderColor(context)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.18 : 0.04),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: dpi.scale(32),
                height: dpi.scale(32),
                decoration: BoxDecoration(
                  color: rankColor.withValues(alpha: isDark ? 0.2 : 0.12),
                  borderRadius: BorderRadius.circular(dpi.radius(8)),
                ),
                alignment: Alignment.center,
                child: Text(
                  '#$rank',
                  style: TextStyle(fontSize: dpi.font(11), fontWeight: FontWeight.w800, color: rankColor),
                ),
              ),
              SizedBox(width: dpi.space(10)),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      product.label,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    SizedBox(height: dpi.space(2)),
                    Text(
                      '${MangoFormatters.number(product.quantity.round())} uds · ${share.toStringAsFixed(1)}% del total',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              SizedBox(width: dpi.space(8)),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  MangoFormatters.currency(product.amount),
                  style: TextStyle(
                    fontSize: dpi.font(14),
                    fontWeight: FontWeight.w800,
                    color: MangoThemeFactory.mango,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: dpi.space(10)),
          Stack(
            children: [
              Container(
                height: dpi.space(6),
                decoration: BoxDecoration(
                  color: MangoThemeFactory.borderColor(context),
                  borderRadius: BorderRadius.circular(dpi.radius(3)),
                ),
              ),
              FractionallySizedBox(
                widthFactor: percent.clamp(0.0, 1.0),
                child: Container(
                  height: dpi.space(6),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [MangoThemeFactory.mango, MangoThemeFactory.mango.withValues(alpha: 0.7)],
                    ),
                    borderRadius: BorderRadius.circular(dpi.radius(3)),
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

/// Reporte Z (cierre de turno) — formato tipo recibo, listo para imprimir.
class ReporteZView extends ConsumerStatefulWidget {
  const ReporteZView({super.key, required this.closing});

  final RegisterClosing closing;

  @override
  ConsumerState<ReporteZView> createState() => _ReporteZViewState();
}

class _ReporteZViewState extends ConsumerState<ReporteZView> {
  late Future<List<NcfTypeSummary>> _ncfsFuture;
  List<NcfTypeSummary> _ncfs = const [];
  bool _ncfsLoading = true;
  bool _ncfsError = false;
  bool _exportInFlight = false;

  @override
  void initState() {
    super.initState();
    _ncfsFuture = _loadNcfs();
  }

  Future<List<NcfTypeSummary>> _loadNcfs() async {
    final profile = ref.read(authGateViewModelProvider).profile;
    final businessId = profile?.businessId;
    if (businessId == null) {
      if (mounted) {
        setState(() {
          _ncfsLoading = false;
          _ncfsError = true;
        });
      }
      return const [];
    }
    try {
      final list = await ref.read(cashRegisterDataServiceProvider).loadNcfsForSession(
            businessId: businessId,
            openedAt: widget.closing.openedAt ??
                widget.closing.closedAt.subtract(const Duration(hours: 24)),
            closedAt: widget.closing.closedAt,
          );
      if (mounted) {
        setState(() {
          _ncfs = list;
          _ncfsLoading = false;
        });
      }
      return list;
    } catch (_) {
      if (mounted) {
        setState(() {
          _ncfsLoading = false;
          _ncfsError = true;
        });
      }
      return const [];
    }
  }

  Future<void> _handlePrint(String businessName) async {
    if (_exportInFlight) return;
    setState(() => _exportInFlight = true);
    try {
      final doc = await ReporteZPdfBuilder.build(
        closing: widget.closing,
        businessName: businessName,
        ncfs: _ncfs,
      );
      await Printing.layoutPdf(
        onLayout: (format) async => doc.save(),
        name: _pdfName(),
      );
    } finally {
      if (mounted) setState(() => _exportInFlight = false);
    }
  }

  Future<void> _handleShare(String businessName) async {
    if (_exportInFlight) return;
    setState(() => _exportInFlight = true);
    try {
      final doc = await ReporteZPdfBuilder.build(
        closing: widget.closing,
        businessName: businessName,
        ncfs: _ncfs,
      );
      final bytes = await doc.save();
      await Printing.sharePdf(bytes: bytes, filename: '${_pdfName()}.pdf');
    } finally {
      if (mounted) setState(() => _exportInFlight = false);
    }
  }

  String _pdfName() {
    final d = widget.closing.closedAt;
    final stamp = '${d.year}${d.month.toString().padLeft(2, '0')}${d.day.toString().padLeft(2, '0')}_${d.hour.toString().padLeft(2, '0')}${d.minute.toString().padLeft(2, '0')}';
    return 'reporte_z_$stamp';
  }

  @override
  Widget build(BuildContext context) {
    final dpi = DpiScale.of(context);
    final auth = ref.watch(authGateViewModelProvider);
    final profile = auth.profile;
    final businessId = profile?.businessId;
    final businessName = profile?.businessName ?? 'Mi Negocio';

    final canExport = !_ncfsLoading && !_exportInFlight && businessId != null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Reporte de cierre'),
        centerTitle: false,
        actions: [
          IconButton(
            tooltip: 'Compartir',
            icon: const Icon(Icons.ios_share_rounded),
            onPressed: canExport ? () => _handleShare(businessName) : null,
          ),
          IconButton(
            tooltip: 'Imprimir',
            icon: const Icon(Icons.print_rounded),
            onPressed: canExport ? () => _handlePrint(businessName) : null,
          ),
          SizedBox(width: dpi.space(4)),
        ],
      ),
      body: businessId == null
          ? const Center(child: Text('No se pudo identificar el negocio.'))
          : FutureBuilder<List<NcfTypeSummary>>(
              future: _ncfsFuture,
              builder: (context, snapshot) {
                return ListView(
                  padding: EdgeInsets.fromLTRB(dpi.space(16), dpi.space(16), dpi.space(16), dpi.space(16) + MediaQuery.of(context).padding.bottom),
                  children: [
                    _ReporteZReceipt(
                      closing: widget.closing,
                      businessName: businessName,
                      ncfs: _ncfs,
                      ncfsLoading: _ncfsLoading,
                      ncfsError: _ncfsError,
                    ),
                  ],
                );
              },
            ),
    );
  }
}

class _ReporteZReceipt extends StatelessWidget {
  const _ReporteZReceipt({
    required this.closing,
    required this.businessName,
    required this.ncfs,
    required this.ncfsLoading,
    required this.ncfsError,
  });

  final RegisterClosing closing;
  final String businessName;
  final List<NcfTypeSummary> ncfs;
  final bool ncfsLoading;
  final bool ncfsError;

  @override
  Widget build(BuildContext context) {
    final dpi = DpiScale.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final openedAt = closing.openedAt;
    final duration = openedAt == null ? null : closing.closedAt.difference(openedAt);
    final cashExpected = closing.openingAmount + closing.cashSales + closing.totalDeposits - closing.totalWithdrawals - closing.totalExpenses;
    final cashDifference = closing.closingAmount - cashExpected;
    final ncfTotalCount = ncfs.fold<int>(0, (s, n) => s + n.count);
    final ncfTotalAmount = ncfs.fold<double>(0, (s, n) => s + n.total);

    return Container(
      padding: EdgeInsets.all(dpi.space(20)),
      decoration: BoxDecoration(
        color: MangoThemeFactory.cardColor(context),
        borderRadius: BorderRadius.circular(dpi.radius(16)),
        border: Border.all(color: MangoThemeFactory.borderColor(context)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.18 : 0.04),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Column(
              children: [
                Text(
                  businessName.toUpperCase(),
                  style: TextStyle(fontSize: dpi.font(15), fontWeight: FontWeight.w900, letterSpacing: 1.2),
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: dpi.space(4)),
                Text(
                  'REPORTE DE CIERRE DE TURNO',
                  style: TextStyle(fontSize: dpi.font(11), fontWeight: FontWeight.w700, color: MangoThemeFactory.mutedText(context), letterSpacing: 1.5),
                ),
              ],
            ),
          ),
          SizedBox(height: dpi.space(14)),
          const _ReceiptDivider(dashed: true),
          SizedBox(height: dpi.space(10)),
          _ReceiptRow(label: 'Caja', value: closing.registerName),
          _ReceiptRow(label: 'Cajero', value: closing.closedByName),
          if (closing.deviceName != null && closing.deviceName!.trim().isNotEmpty)
            _ReceiptRow(label: 'Dispositivo', value: closing.deviceName!),
          if (openedAt != null)
            _ReceiptRow(label: 'Apertura', value: MangoFormatters.dateTime(openedAt)),
          _ReceiptRow(label: 'Cierre', value: MangoFormatters.dateTime(closing.closedAt)),
          if (duration != null)
            _ReceiptRow(label: 'Duración', value: _formatDuration(duration)),
          SizedBox(height: dpi.space(12)),
          const _ReceiptDivider(),
          const _ReceiptSectionTitle('VENTAS'),
          _ReceiptRow(label: 'Efectivo', value: MangoFormatters.currency(closing.cashSales)),
          _ReceiptRow(label: 'Tarjeta', value: MangoFormatters.currency(closing.cardSales)),
          _ReceiptRow(label: 'Transferencia', value: MangoFormatters.currency(closing.transferSales)),
          if (closing.otherSales > 0)
            _ReceiptRow(label: 'Otros', value: MangoFormatters.currency(closing.otherSales)),
          SizedBox(height: dpi.space(4)),
          _ReceiptRow(
            label: 'TOTAL VENTAS',
            value: MangoFormatters.currency(closing.totalSales),
            emphasis: true,
          ),
          SizedBox(height: dpi.space(12)),
          const _ReceiptDivider(),
          const _ReceiptSectionTitle('CAJA EN EFECTIVO'),
          _ReceiptRow(label: 'Apertura', value: MangoFormatters.currency(closing.openingAmount)),
          _ReceiptRow(label: '+ Ventas efectivo', value: MangoFormatters.currency(closing.cashSales)),
          _ReceiptRow(label: '+ Depósitos', value: MangoFormatters.currency(closing.totalDeposits)),
          _ReceiptRow(label: '− Retiros', value: MangoFormatters.currency(closing.totalWithdrawals)),
          _ReceiptRow(label: '− Gastos', value: MangoFormatters.currency(closing.totalExpenses)),
          SizedBox(height: dpi.space(4)),
          _ReceiptRow(label: 'Esperado', value: MangoFormatters.currency(cashExpected), emphasis: true),
          _ReceiptRow(label: 'Contado al cierre', value: MangoFormatters.currency(closing.closingAmount), emphasis: true),
          SizedBox(height: dpi.space(4)),
          _ReceiptRow(
            label: cashDifference == 0 ? 'Diferencia' : (cashDifference > 0 ? 'Sobrante' : 'Faltante'),
            value: MangoFormatters.currency(cashDifference.abs()),
            valueColor: cashDifference == 0
                ? null
                : cashDifference > 0
                    ? MangoThemeFactory.success
                    : MangoThemeFactory.danger,
            emphasis: true,
          ),
          SizedBox(height: dpi.space(12)),
          const _ReceiptDivider(),
          const _ReceiptSectionTitle('COMPROBANTES FISCALES (NCF)'),
          if (ncfsLoading)
            Padding(
              padding: EdgeInsets.symmetric(vertical: dpi.space(10)),
              child: const Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))),
            )
          else if (ncfsError)
            Padding(
              padding: EdgeInsets.symmetric(vertical: dpi.space(8)),
              child: Text(
                'No se pudo cargar la información fiscal.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: MangoThemeFactory.danger),
              ),
            )
          else if (ncfs.isEmpty)
            Padding(
              padding: EdgeInsets.symmetric(vertical: dpi.space(8)),
              child: Text(
                'Sin NCFs emitidos en este turno.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            )
          else ...[
            for (final ncf in ncfs) ...[
              _ReceiptRow(
                label: '${ncf.type} (${ncf.count})',
                value: MangoFormatters.currency(ncf.total),
              ),
              if (ncf.firstNumber != null && ncf.lastNumber != null)
                Padding(
                  padding: EdgeInsets.only(left: dpi.space(8), bottom: dpi.space(4)),
                  child: Text(
                    ncf.firstNumber == ncf.lastNumber
                        ? ncf.firstNumber!
                        : '${ncf.firstNumber} → ${ncf.lastNumber}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontFamily: 'monospace',
                          fontSize: dpi.font(10),
                          color: MangoThemeFactory.mutedText(context),
                        ),
                  ),
                ),
            ],
            SizedBox(height: dpi.space(4)),
            _ReceiptRow(label: 'Total NCFs', value: '$ncfTotalCount comprobantes', emphasis: true),
            _ReceiptRow(label: 'Total facturado', value: MangoFormatters.currency(ncfTotalAmount), emphasis: true),
          ],
          SizedBox(height: dpi.space(16)),
          const _ReceiptDivider(dashed: true),
          SizedBox(height: dpi.space(20)),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: dpi.space(20)),
            child: Container(height: 1, color: MangoThemeFactory.textColor(context)),
          ),
          SizedBox(height: dpi.space(4)),
          Center(
            child: Text(
              'Firma cajero',
              style: TextStyle(fontSize: dpi.font(11), color: MangoThemeFactory.mutedText(context)),
            ),
          ),
          SizedBox(height: dpi.space(20)),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: dpi.space(20)),
            child: Container(height: 1, color: MangoThemeFactory.textColor(context)),
          ),
          SizedBox(height: dpi.space(4)),
          Center(
            child: Text(
              'Firma supervisor',
              style: TextStyle(fontSize: dpi.font(11), color: MangoThemeFactory.mutedText(context)),
            ),
          ),
          SizedBox(height: dpi.space(16)),
          Center(
            child: Text(
              'Generado: ${MangoFormatters.dateTime(DateTime.now())}',
              style: TextStyle(fontSize: dpi.font(9), color: MangoThemeFactory.mutedText(context)),
            ),
          ),
        ],
      ),
    );
  }

  static String _formatDuration(Duration d) {
    final hours = d.inHours;
    final minutes = d.inMinutes.remainder(60);
    if (hours == 0) return '${minutes}m';
    return '${hours}h ${minutes}m';
  }
}

class _ReceiptRow extends StatelessWidget {
  const _ReceiptRow({
    required this.label,
    required this.value,
    this.emphasis = false,
    this.valueColor,
  });

  final String label;
  final String value;
  final bool emphasis;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final dpi = DpiScale.of(context);
    final style = TextStyle(
      fontSize: dpi.font(emphasis ? 13 : 12),
      fontWeight: emphasis ? FontWeight.w800 : FontWeight.w500,
      color: MangoThemeFactory.textColor(context),
    );
    return Padding(
      padding: EdgeInsets.symmetric(vertical: dpi.space(2)),
      child: Row(
        children: [
          Expanded(child: Text(label, style: style.copyWith(fontWeight: emphasis ? FontWeight.w700 : FontWeight.w500))),
          Text(value, style: style.copyWith(color: valueColor ?? style.color)),
        ],
      ),
    );
  }
}

class _ReceiptSectionTitle extends StatelessWidget {
  const _ReceiptSectionTitle(this.title);
  final String title;

  @override
  Widget build(BuildContext context) {
    final dpi = DpiScale.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: dpi.space(6)),
      child: Text(
        title,
        style: TextStyle(
          fontSize: dpi.font(11),
          fontWeight: FontWeight.w900,
          letterSpacing: 1.2,
          color: MangoThemeFactory.mango,
        ),
      ),
    );
  }
}

class _ReceiptDivider extends StatelessWidget {
  const _ReceiptDivider({this.dashed = false});
  final bool dashed;

  @override
  Widget build(BuildContext context) {
    final dpi = DpiScale.of(context);
    final color = MangoThemeFactory.borderColor(context);
    if (!dashed) {
      return Container(height: 1, color: color, margin: EdgeInsets.symmetric(vertical: dpi.space(2)));
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        const dashWidth = 4.0;
        const dashSpace = 4.0;
        final dashCount = (constraints.maxWidth / (dashWidth + dashSpace)).floor();
        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: List.generate(dashCount, (_) => SizedBox(
            width: dashWidth,
            height: 1,
            child: DecoratedBox(decoration: BoxDecoration(color: color)),
          )),
        );
      },
    );
  }
}
