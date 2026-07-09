import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:printing/printing.dart';

import '../../../app/di/providers.dart';
import '../../../core/formatters/mango_formatters.dart';
import '../../../core/date/date_range_utils.dart';
import '../../../core/responsive/dpi_scale.dart';
import '../../../data/cash_register/reporte_z_pdf_builder.dart';
import '../../../data/export/report_export_service.dart';
import '../../../domain/dashboard/dashboard_models.dart';
import '../../auth/viewmodel/auth_gate_view_model.dart';
import '../viewmodel/cash_register_view_model.dart';
import '../../theme/theme_data_factory.dart';
import '../widgets/growth_chip.dart';
import '../widgets/period_filter_bar.dart';

/// Ventas del día - lista de todos los tickets/pagos
class SalesDetailView extends ConsumerStatefulWidget {
  const SalesDetailView({super.key, required this.summary});

  final DashboardSummary summary;

  @override
  ConsumerState<SalesDetailView> createState() => _SalesDetailViewState();
}

class _SalesDetailViewState extends ConsumerState<SalesDetailView> {
  late DateTime _start;
  late DateTime _end;
  late String _periodLabel;
  DetailPeriod _period = DetailPeriod.initial;
  DateTimeRange? _customRange;
  String _query = '';

  late List<TicketItem> _tickets;
  late double _totalSales;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _start = widget.summary.periodStart ??
        DateTime.now().subtract(const Duration(days: 1));
    _end = widget.summary.periodEnd ?? DateTime.now();
    _periodLabel = periodLabelFor(widget.summary.filter);
    _tickets = widget.summary.tickets;
    _totalSales = widget.summary.totalSales;
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final businessId = widget.summary.profile.businessId;
      final result = await ref
          .read(dashboardDataServiceProvider)
          .loadTicketsForPeriod(
            businessId: businessId,
            start: _start,
            end: _end,
          );
      if (!mounted) return;
      setState(() {
        _tickets = result.tickets;
        _totalSales = result.totalSales;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'No se pudo cargar las ventas.';
      });
    }
  }

  void _applyPeriod(DetailPeriod period) {
    if (period == DetailPeriod.initial) {
      setState(() {
        _period = DetailPeriod.initial;
        _start = widget.summary.periodStart ??
            DateTime.now().subtract(const Duration(days: 1));
        _end = widget.summary.periodEnd ?? DateTime.now();
        _periodLabel = periodLabelFor(widget.summary.filter);
      });
      _reload();
      return;
    }
    final range = rangeForDetailPeriod(period, DateTime.now());
    if (range == null) return;
    setState(() {
      _period = period;
      _start = range.start;
      _end = range.end;
      _periodLabel = labelForDetailPeriod(period);
    });
    _reload();
  }

  Future<void> _pickCustomRange() async {
    final now = DateTime.now();
    final firstDate = DateTime(now.year - 3);
    final lastDate = DateTime(now.year, now.month, now.day);
    // Preset periods can end in the future (e.g. "este mes"); clamp the seed
    // into the picker bounds so its assertions hold.
    final seed = clampInitialDateRange(
      start: _customRange?.start ?? _start,
      end: _customRange?.end ?? _end.subtract(const Duration(days: 1)),
      firstDate: firstDate,
      lastDate: lastDate,
    );
    final picked = await showDateRangePicker(
      context: context,
      firstDate: firstDate,
      lastDate: lastDate,
      initialDateRange: seed,
    );
    if (picked == null || !mounted) return;
    final start = DateTime(picked.start.year, picked.start.month, picked.start.day);
    final end = DateTime(picked.end.year, picked.end.month, picked.end.day)
        .add(const Duration(days: 1));
    setState(() {
      _period = DetailPeriod.custom;
      _customRange = picked;
      _start = start;
      _end = end;
      _periodLabel = labelForDetailPeriod(DetailPeriod.custom, customRange: picked);
    });
    _reload();
  }

  List<TicketItem> get _filteredTickets {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return _tickets;
    return _tickets
        .where((t) =>
            t.orderId.toLowerCase().contains(q) ||
            (t.paymentMethodCode ?? '').toLowerCase().contains(q))
        .toList();
  }

  List<List<String>> _rowsForExport() {
    return _filteredTickets
        .map((t) => [
              t.orderId,
              _formatDateTime(t.createdAt),
              t.paymentMethodCode ?? '',
              t.amount.toStringAsFixed(2),
            ])
        .toList();
  }

  Future<void> _exportCsv() async {
    await ReportExportService.exportCsv(
      filename: 'ventas_${_periodLabel.replaceAll(' ', '_')}',
      headers: const ['Orden', 'Fecha', 'Método', 'Monto'],
      rows: _rowsForExport(),
      subject: 'Reporte de ventas · $_periodLabel',
    );
  }

  Future<void> _exportPdf() async {
    await ReportExportService.exportPdf(
      filename: 'ventas_${_periodLabel.replaceAll(' ', '_')}',
      title: 'Ventas',
      subtitle: 'Periodo: $_periodLabel · Total: '
          '${MangoFormatters.currency(_totalSales)}',
      headers: const ['Orden', 'Fecha', 'Método', 'Monto'],
      rows: _rowsForExport(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dpi = DpiScale.of(context);
    final tickets = _filteredTickets;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ventas'),
        centerTitle: false,
        actions: [
          ExportMenuButton(
            enabled: _tickets.isNotEmpty,
            onExportCsv: _exportCsv,
            onExportPdf: _exportPdf,
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(
                dpi.space(16), dpi.space(16), dpi.space(16), 0),
            child: _SalesSummaryHeader(
              totalSales: _totalSales,
              totalTickets: tickets.length,
              periodLabel: _periodLabel,
            ),
          ),
          SizedBox(height: dpi.space(12)),
          PeriodFilterBar(
            selected: _period,
            customRange: _customRange,
            initialLabel: periodLabelFor(widget.summary.filter),
            onSelected: _applyPeriod,
            onPickCustom: _pickCustomRange,
            accent: MangoThemeFactory.success,
          ),
          SizedBox(height: dpi.space(10)),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: dpi.space(16)),
            child: TextField(
              onChanged: (v) => setState(() => _query = v),
              decoration: InputDecoration(
                hintText: 'Buscar por orden o método de pago…',
                prefixIcon: const Icon(Icons.search_rounded),
                isDense: true,
                contentPadding: EdgeInsets.symmetric(
                    horizontal: dpi.space(12), vertical: dpi.space(12)),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(dpi.radius(12))),
              ),
            ),
          ),
          SizedBox(height: dpi.space(10)),
          Expanded(
            child: Builder(builder: (context) {
              if (_loading) {
                return const Center(child: CircularProgressIndicator());
              }
              if (_error != null) {
                return Center(
                  child: Padding(
                    padding: EdgeInsets.all(dpi.space(20)),
                    child: Text(_error!,
                        style: TextStyle(color: MangoThemeFactory.danger),
                        textAlign: TextAlign.center),
                  ),
                );
              }
              if (tickets.isEmpty) {
                return Center(
                  child: Text(
                    _query.isEmpty
                        ? 'No hay ventas en este periodo.'
                        : 'Sin resultados para "$_query".',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                );
              }
              return ListView.builder(
                padding: EdgeInsets.fromLTRB(
                    dpi.space(16),
                    0,
                    dpi.space(16),
                    dpi.space(16) + MediaQuery.of(context).padding.bottom),
                itemCount: tickets.length,
                itemBuilder: (context, index) =>
                    _TicketCard(ticket: tickets[index], index: index + 1),
              );
            }),
          ),
        ],
      ),
    );
  }
}

String _formatDateTime(DateTime t) {
  final h = t.hour.toString().padLeft(2, '0');
  final m = t.minute.toString().padLeft(2, '0');
  return '${t.day}/${t.month}/${t.year} $h:$m';
}

class _SalesSummaryHeader extends StatelessWidget {
  const _SalesSummaryHeader({
    required this.totalSales,
    required this.totalTickets,
    required this.periodLabel,
  });
  final double totalSales;
  final int totalTickets;
  final String periodLabel;

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
                  'Ventas · $periodLabel',
                  style: TextStyle(color: Colors.white70, fontSize: dpi.font(12), fontWeight: FontWeight.w500),
                ),
                SizedBox(height: dpi.space(4)),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    MangoFormatters.currency(totalSales),
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
                '$totalTickets',
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

class CashRegisterDetailView extends ConsumerWidget {
  const CashRegisterDetailView({super.key, this.summary, this.error});

  final CashRegisterSummary? summary;
  final String? error;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dpi = DpiScale.of(context);
    // Watch the provider so a force-close (which reloads it) refreshes this view;
    // fall back to the snapshot passed in for the first frame.
    final state = ref.watch(cashRegisterViewModelProvider);
    final data = state.summary ?? summary;
    final err = state.error ?? error;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Cierres de Caja'),
        centerTitle: false,
      ),
      body: err != null
          ? Center(child: Text(err, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.red)))
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
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => _OpenRegisterDetailSheet(session: session),
      ),
      child: Container(
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
      ),
    );
  }
}

/// Detail sheet for an OPEN register — shows the same reconciliation the closed
/// sessions show (expected per method), computed live, plus a force-close action.
class _OpenRegisterDetailSheet extends ConsumerStatefulWidget {
  const _OpenRegisterDetailSheet({required this.session});
  final RegisterSession session;

  @override
  ConsumerState<_OpenRegisterDetailSheet> createState() =>
      _OpenRegisterDetailSheetState();
}

class _OpenRegisterDetailSheetState
    extends ConsumerState<_OpenRegisterDetailSheet> {
  bool _closing = false;

  @override
  Widget build(BuildContext context) {
    final dpi = DpiScale.of(context);
    final s = widget.session;
    return SafeArea(
      top: false,
      child: Container(
        constraints:
            BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85),
        padding: EdgeInsets.fromLTRB(
            dpi.space(20), dpi.space(16), dpi.space(20), dpi.space(20)),
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(dpi.radius(24))),
        ),
        child: ListView(
          shrinkWrap: true,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(s.registerName,
                          style: Theme.of(context)
                              .textTheme
                              .titleLarge
                              ?.copyWith(fontWeight: FontWeight.w800)),
                      Text('Abierta por ${s.openedByName}',
                          style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
                ),
                Container(
                  padding: EdgeInsets.symmetric(
                      horizontal: dpi.space(10), vertical: dpi.space(4)),
                  decoration: BoxDecoration(
                    color: MangoThemeFactory.success.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(dpi.radius(8)),
                  ),
                  child: Text('ABIERTA',
                      style: TextStyle(
                          fontSize: dpi.font(10),
                          fontWeight: FontWeight.w800,
                          color: MangoThemeFactory.success)),
                ),
              ],
            ),
            SizedBox(height: dpi.space(16)),
            _title(context, 'Ventas por método'),
            _row(context, 'Efectivo', s.cashSales),
            _row(context, 'Tarjeta', s.cardSales),
            _row(context, 'Transferencia', s.transferSales),
            if (s.otherSales > 0) _row(context, 'Otros', s.otherSales),
            _row(context, 'Total ventas', s.totalSales, bold: true),
            SizedBox(height: dpi.space(14)),
            _title(context, 'Movimientos de caja'),
            _row(context, 'Apertura', s.openingAmount),
            _row(context, '+ Depósitos', s.totalDeposits),
            _row(context, '− Retiros', s.totalWithdrawals),
            _row(context, '− Gastos', s.totalExpenses),
            SizedBox(height: dpi.space(14)),
            _title(context, 'Esperado en caja'),
            _row(context, 'Esperado efectivo', s.expectedCash),
            _row(context, 'Esperado tarjeta', s.expectedCard),
            _row(context, 'Esperado transferencia', s.expectedTransfer),
            _row(context, 'Total esperado', s.expectedTotal, bold: true),
            SizedBox(height: dpi.space(20)),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _closing ? null : _confirmForceClose,
                style: FilledButton.styleFrom(
                  backgroundColor: MangoThemeFactory.warning,
                  padding: EdgeInsets.symmetric(vertical: dpi.space(14)),
                ),
                icon: _closing
                    ? SizedBox(
                        width: dpi.icon(16),
                        height: dpi.icon(16),
                        child: const CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.lock_clock_rounded),
                label: Text(_closing ? 'Cerrando…' : 'Forzar cierre de caja'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _title(BuildContext context, String text) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(text.toUpperCase(),
            style: TextStyle(
                fontSize: DpiScale.of(context).font(10),
                fontWeight: FontWeight.w800,
                letterSpacing: 0.6,
                color: MangoThemeFactory.mutedText(context))),
      );

  Widget _row(BuildContext context, String label, double value,
          {bool bold = false}) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label,
                style: TextStyle(
                    fontWeight: bold ? FontWeight.w800 : FontWeight.w400)),
            Text(MangoFormatters.currency(value),
                style: TextStyle(
                    fontWeight: bold ? FontWeight.w800 : FontWeight.w600)),
          ],
        ),
      );

  Future<void> _confirmForceClose() async {
    final result = await showDialog<_ForceCloseInput>(
      context: context,
      builder: (_) =>
          _ForceCloseDialog(expectedTotal: widget.session.expectedTotal),
    );
    if (result == null || !mounted) return;
    setState(() => _closing = true);
    final err =
        await ref.read(cashRegisterViewModelProvider.notifier).forceClose(
              sessionId: widget.session.id,
              reason: result.reason,
              endAmount: result.countedCash,
            );
    if (!mounted) return;
    setState(() => _closing = false);
    final messenger = ScaffoldMessenger.of(context);
    if (err == null) {
      Navigator.of(context).pop();
      messenger.showSnackBar(SnackBar(
          content: Text('Caja "${widget.session.registerName}" cerrada.')));
    } else {
      messenger.showSnackBar(SnackBar(content: Text(err)));
    }
  }
}

class _ForceCloseInput {
  const _ForceCloseInput(this.reason, this.countedCash);
  final String reason;
  final double? countedCash;
}

class _ForceCloseDialog extends StatefulWidget {
  const _ForceCloseDialog({required this.expectedTotal});
  final double expectedTotal;

  @override
  State<_ForceCloseDialog> createState() => _ForceCloseDialogState();
}

class _ForceCloseDialogState extends State<_ForceCloseDialog> {
  final _reason = TextEditingController();
  final _amount = TextEditingController();
  bool _submitted = false;

  @override
  void dispose() {
    _reason.dispose();
    _amount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reasonEmpty = _reason.text.trim().isEmpty;
    return AlertDialog(
      title: const Text('Forzar cierre de caja'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Cerrarás esta caja como owner. Se cerrará aunque haya mesas u '
            'órdenes abiertas. Total esperado: '
            '${MangoFormatters.currency(widget.expectedTotal)}.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _reason,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: 'Motivo (obligatorio)',
              errorText: _submitted && reasonEmpty ? 'Escribe un motivo' : null,
              border: const OutlineInputBorder(),
            ),
            maxLines: 2,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _amount,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Efectivo contado (opcional)',
              helperText: 'En blanco = cierra sin cuadre',
              prefixText: 'RD\$ ',
              border: OutlineInputBorder(),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () {
            setState(() => _submitted = true);
            if (_reason.text.trim().isEmpty) return;
            final raw = _amount.text.trim().replaceAll(',', '.');
            Navigator.of(context).pop(
              _ForceCloseInput(
                _reason.text.trim(),
                raw.isEmpty ? null : double.tryParse(raw),
              ),
            );
          },
          child: const Text('Forzar cierre'),
        ),
      ],
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
                    if (closing.netDifference != 0) ...[
                      SizedBox(height: dpi.space(4)),
                      Text(
                        // Net (all-method) difference — reportedTotal − expectedTotal.
                        '${closing.netDifference > 0 ? 'Sobrante' : 'Faltante'}: ${_signedCurrency(closing.netDifference)}'
                        '${closing.hasReportedBreakdown ? '' : ' (efectivo)'}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: _diffColor(context, closing.netDifference),
                            ),
                      ),
                    ],
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

class _ClosingDetailSheet extends ConsumerStatefulWidget {
  const _ClosingDetailSheet({required this.closing});

  final RegisterClosing closing;

  @override
  ConsumerState<_ClosingDetailSheet> createState() => _ClosingDetailSheetState();
}

class _ClosingDetailSheetState extends ConsumerState<_ClosingDetailSheet> {
  CashCloseDetail? _detail;
  bool _loading = true;
  bool _failed = false;

  RegisterClosing get closing => widget.closing;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final detail =
          await ref.read(cashRegisterDataServiceProvider).loadCloseDetail(closing);
      if (!mounted) return;
      setState(() {
        _detail = detail;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _failed = true;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final dpi = DpiScale.of(context);
    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.5,
      maxChildSize: 0.95,
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
              if (_loading)
                Padding(
                  padding: EdgeInsets.symmetric(vertical: dpi.space(40)),
                  child: const Center(child: CircularProgressIndicator()),
                )
              else if (_failed || _detail == null)
                Padding(
                  padding: EdgeInsets.symmetric(vertical: dpi.space(24)),
                  child: Center(
                    child: Text(
                      'No se pudo cargar el detalle del cierre.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: MangoThemeFactory.danger),
                    ),
                  ),
                )
              else
                ..._buildReconciled(context, dpi, _detail!),
            ],
          ),
        );
      },
    );
  }

  List<Widget> _buildReconciled(BuildContext context, DpiScale dpi, CashCloseDetail d) {
    final muted = MangoThemeFactory.mutedText(context);
    final reportedTotal = d.reportedTotal;
    final net = d.netDifference;
    final netColor = _diffColor(context, net);
    final netLabel = net == 0 ? 'Cuadrado' : (net > 0 ? 'Sobrante' : 'Faltante');

    return [
      _sectionTitle(context, 'Cómo abrió'),
      SizedBox(height: dpi.space(10)),
      _MetricCard(icon: Icons.lock_open_rounded, color: MangoThemeFactory.mango, label: 'Monto apertura', value: MangoFormatters.currency(d.startAmount)),

      SizedBox(height: dpi.space(18)),
      _sectionTitle(context, 'Qué hubo en la caja'),
      SizedBox(height: dpi.space(10)),
      _MetricCard(
        icon: Icons.payments_rounded,
        color: MangoThemeFactory.success,
        label: 'Ventas totales',
        value: MangoFormatters.currency(d.totalSales),
        subtitle: 'Toca para ver por método',
        onTap: () => _openSalesBreakdown(d),
      ),
      SizedBox(height: dpi.space(8)),
      Padding(
        padding: EdgeInsets.only(left: dpi.space(4)),
        child: Wrap(
          spacing: dpi.space(10),
          runSpacing: dpi.space(6),
          children: [
            if (d.cashSales > 0)
              _PayMethodChip(icon: Icons.payments_rounded, label: MangoFormatters.currency(d.cashSales), color: MangoThemeFactory.success),
            if (d.cardSales > 0)
              _PayMethodChip(icon: Icons.credit_card_rounded, label: MangoFormatters.currency(d.cardSales), color: Colors.blueAccent),
            if (d.transferSales > 0)
              _PayMethodChip(icon: Icons.swap_horiz_rounded, label: MangoFormatters.currency(d.transferSales), color: Colors.deepPurpleAccent),
          ],
        ),
      ),
      SizedBox(height: dpi.space(10)),
      _MetricCard(
        icon: Icons.add_circle_outline_rounded,
        color: MangoThemeFactory.info,
        label: 'Depósitos',
        value: MangoFormatters.currency(d.totalDeposits),
        count: d.transactions.where((t) => t.type == 'deposit').length,
        onTap: () => _openTransactions(d, 'deposit', 'Depósitos', Icons.add_circle_outline_rounded, MangoThemeFactory.info),
      ),
      SizedBox(height: dpi.space(10)),
      _MetricCard(
        icon: Icons.remove_circle_outline_rounded,
        color: MangoThemeFactory.warning,
        label: 'Retiros',
        value: MangoFormatters.currency(d.totalWithdrawals),
        count: d.transactions.where((t) => t.type == 'withdrawal').length,
        onTap: () => _openTransactions(d, 'withdrawal', 'Retiros', Icons.remove_circle_outline_rounded, MangoThemeFactory.warning),
      ),
      SizedBox(height: dpi.space(10)),
      _MetricCard(
        icon: Icons.receipt_rounded,
        color: Colors.redAccent,
        label: 'Gastos',
        value: MangoFormatters.currency(d.totalExpenses),
        count: d.transactions.where((t) => t.type == 'expense').length,
        onTap: () => _openTransactions(d, 'expense', 'Gastos', Icons.receipt_rounded, Colors.redAccent),
      ),

      SizedBox(height: dpi.space(18)),
      _sectionTitle(context, 'Esperado por método'),
      SizedBox(height: dpi.space(10)),
      _BreakdownCard(
        rows: [
          _BreakdownRow('Esperado efectivo', MangoFormatters.currency(d.expectedCash)),
          _BreakdownRow('Esperado tarjeta', MangoFormatters.currency(d.expectedCard)),
          _BreakdownRow('Esperado transferencia', MangoFormatters.currency(d.expectedTransfer)),
        ],
      ),

      SizedBox(height: dpi.space(18)),
      _sectionTitle(context, 'Cómo cerró'),
      SizedBox(height: dpi.space(10)),
      _BreakdownCard(
        rows: [
          _BreakdownRow('Total esperado', MangoFormatters.currency(d.expectedTotalResolved)),
          _BreakdownRow(
            'Total reportado',
            MangoFormatters.currency(reportedTotal),
            muted: !d.hasReported,
          ),
          _BreakdownRow(
            'Dif. efectivo (gaveta)',
            _signedCurrency(d.cashDrawerDifference),
            valueColor: muted,
            muted: true,
          ),
        ],
      ),
      SizedBox(height: dpi.space(10)),
      _MetricCard(
        icon: net == 0
            ? Icons.check_circle_outline_rounded
            : (net > 0 ? Icons.trending_up_rounded : Icons.trending_down_rounded),
        color: netColor,
        label: 'Diferencia',
        value: _signedCurrency(net),
        valueColor: netColor,
        subtitle: d.hasReported
            ? '$netLabel · reportado − esperado'
            : '$netLabel · solo efectivo (sin desglose reportado)',
        onTap: () => _openMethodDifference(d),
      ),

      SizedBox(height: dpi.space(18)),
      _sectionTitle(context, 'Diferencia por método'),
      SizedBox(height: dpi.space(10)),
      if (!d.hasReported) ...[
        Padding(
          padding: EdgeInsets.only(left: dpi.space(4), bottom: dpi.space(8)),
          child: Text(
            'Este cierre no registró el desglose reportado por método. La diferencia mostrada es solo de efectivo (gaveta).',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: muted),
          ),
        ),
      ],
      _BreakdownCard(
        rows: [
          _BreakdownRow('Efectivo', _signedCurrency(d.diffCash), valueColor: _diffColor(context, d.diffCash)),
          _BreakdownRow('Tarjeta', _signedCurrency(d.diffCard), valueColor: _diffColor(context, d.diffCard)),
          _BreakdownRow('Transferencia', _signedCurrency(d.diffTransfer), valueColor: _diffColor(context, d.diffTransfer)),
        ],
      ),

      if (d.forcedCloseNote != null) ...[
        SizedBox(height: dpi.space(14)),
        Container(
          padding: EdgeInsets.all(dpi.space(12)),
          decoration: BoxDecoration(
            color: MangoThemeFactory.warning.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(dpi.radius(12)),
            border: Border.all(color: MangoThemeFactory.warning.withValues(alpha: 0.4)),
          ),
          child: Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: MangoThemeFactory.warning, size: dpi.icon(20)),
              SizedBox(width: dpi.space(10)),
              Expanded(
                child: Text(d.forcedCloseNote!, style: Theme.of(context).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        ),
      ],

      if (closing.notes != null && closing.notes!.trim().isNotEmpty) ...[
        SizedBox(height: dpi.space(18)),
        _sectionTitle(context, 'Notas del cierre'),
        SizedBox(height: dpi.space(10)),
        Container(
          width: double.infinity,
          padding: EdgeInsets.all(dpi.space(12)),
          decoration: BoxDecoration(
            color: MangoThemeFactory.altSurface(context),
            borderRadius: BorderRadius.circular(dpi.radius(12)),
            border: Border.all(color: MangoThemeFactory.borderColor(context)),
          ),
          child: Text(closing.notes!.trim(), style: Theme.of(context).textTheme.bodySmall),
        ),
      ],

      SizedBox(height: dpi.space(24)),
    ];
  }

  Widget _sectionTitle(BuildContext context, String text) =>
      Text(text, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800));

  void _openTransactions(CashCloseDetail d, String type, String title, IconData icon, Color color) {
    final entries = d.transactions.where((t) => t.type == type).toList(growable: false);
    final total = entries.fold<double>(0, (sum, t) => sum + t.amount);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _TransactionListSheet(title: title, icon: icon, color: color, total: total, entries: entries),
    );
  }

  void _openSalesBreakdown(CashCloseDetail d) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _InfoSheet(
        title: 'Ventas por método',
        icon: Icons.payments_rounded,
        color: MangoThemeFactory.success,
        rows: [
          _BreakdownRow('Efectivo', MangoFormatters.currency(d.cashSales)),
          _BreakdownRow('Tarjeta', MangoFormatters.currency(d.cardSales)),
          _BreakdownRow('Transferencia', MangoFormatters.currency(d.transferSales)),
          _BreakdownRow('Total ventas', MangoFormatters.currency(d.totalSales), bold: true),
        ],
        footnote: d.transactionCount > 0 ? '${d.transactionCount} transacciones en el turno.' : null,
      ),
    );
  }

  void _openMethodDifference(CashCloseDetail d) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _InfoSheet(
        title: 'Cómo se calcula la diferencia',
        icon: Icons.compare_arrows_rounded,
        color: _diffColor(ctx, d.netDifference),
        rows: [
          _BreakdownRow('Total reportado', MangoFormatters.currency(d.reportedTotal)),
          _BreakdownRow('Total esperado', MangoFormatters.currency(d.expectedTotalResolved)),
          _BreakdownRow('Diferencia neta', _signedCurrency(d.netDifference), bold: true, valueColor: _diffColor(ctx, d.netDifference)),
          _BreakdownRow('· Efectivo', _signedCurrency(d.diffCash), valueColor: _diffColor(ctx, d.diffCash)),
          _BreakdownRow('· Tarjeta', _signedCurrency(d.diffCard), valueColor: _diffColor(ctx, d.diffCard)),
          _BreakdownRow('· Transferencia', _signedCurrency(d.diffTransfer), valueColor: _diffColor(ctx, d.diffTransfer)),
        ],
        footnote: 'La "Dif. efectivo (gaveta)" solo concilia el efectivo; la diferencia real es la neta entre todos los métodos.',
      ),
    );
  }
}

Color _diffColor(BuildContext context, double v) {
  if (v == 0) return MangoThemeFactory.mutedText(context);
  return v > 0 ? MangoThemeFactory.success : MangoThemeFactory.danger;
}

String _signedCurrency(double v) {
  if (v == 0) return MangoFormatters.currency(0);
  final sign = v > 0 ? '+' : '−';
  return '$sign${MangoFormatters.currency(v.abs())}';
}

class _BreakdownRow {
  const _BreakdownRow(this.label, this.value, {this.valueColor, this.bold = false, this.muted = false});
  final String label;
  final String value;
  final Color? valueColor;
  final bool bold;
  final bool muted;
}

class _BreakdownCard extends StatelessWidget {
  const _BreakdownCard({required this.rows});
  final List<_BreakdownRow> rows;

  @override
  Widget build(BuildContext context) {
    final dpi = DpiScale.of(context);
    final muted = MangoThemeFactory.mutedText(context);
    return Container(
      padding: EdgeInsets.symmetric(horizontal: dpi.space(14), vertical: dpi.space(6)),
      decoration: BoxDecoration(
        color: MangoThemeFactory.cardColor(context),
        borderRadius: BorderRadius.circular(dpi.radius(16)),
        border: Border.all(color: MangoThemeFactory.borderColor(context)),
      ),
      child: Column(
        children: [
          for (final row in rows)
            Padding(
              padding: EdgeInsets.symmetric(vertical: dpi.space(8)),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Flexible(
                    child: Text(
                      row.label,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: row.muted ? muted : null,
                            fontWeight: row.bold ? FontWeight.w700 : null,
                          ),
                    ),
                  ),
                  SizedBox(width: dpi.space(10)),
                  Text(
                    row.value,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: row.bold ? FontWeight.w800 : FontWeight.w700,
                          color: row.valueColor ?? (row.muted ? muted : MangoThemeFactory.textColor(context)),
                        ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Bottom sheet listing the individual cash movements of a given type, including
/// each movement's note/description — so the user can see what every expense or
/// withdrawal was for.
class _TransactionListSheet extends StatelessWidget {
  const _TransactionListSheet({
    required this.title,
    required this.icon,
    required this.color,
    required this.total,
    required this.entries,
  });

  final String title;
  final IconData icon;
  final Color color;
  final double total;
  final List<CashTransactionEntry> entries;

  @override
  Widget build(BuildContext context) {
    final dpi = DpiScale.of(context);
    return DraggableScrollableSheet(
      initialChildSize: 0.55,
      minChildSize: 0.35,
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
                  decoration: BoxDecoration(color: MangoThemeFactory.borderColor(context), borderRadius: BorderRadius.circular(999)),
                ),
              ),
              SizedBox(height: dpi.space(18)),
              Row(
                children: [
                  Container(
                    width: dpi.scale(40),
                    height: dpi.scale(40),
                    decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(dpi.radius(12))),
                    child: Icon(icon, color: color, size: dpi.icon(20)),
                  ),
                  SizedBox(width: dpi.space(12)),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title, style: Theme.of(context).textTheme.titleLarge),
                        Text('${entries.length} movimiento(s)', style: Theme.of(context).textTheme.bodySmall),
                      ],
                    ),
                  ),
                  Text(MangoFormatters.currency(total), style: TextStyle(fontSize: dpi.font(16), fontWeight: FontWeight.w800, color: color)),
                ],
              ),
              SizedBox(height: dpi.space(16)),
              if (entries.isEmpty)
                Padding(
                  padding: EdgeInsets.symmetric(vertical: dpi.space(24)),
                  child: Center(
                    child: Text('Sin movimientos registrados.', style: Theme.of(context).textTheme.bodySmall),
                  ),
                )
              else
                for (final entry in entries) ...[
                  Container(
                    margin: EdgeInsets.only(bottom: dpi.space(8)),
                    padding: EdgeInsets.all(dpi.space(12)),
                    decoration: BoxDecoration(
                      color: MangoThemeFactory.altSurface(context),
                      borderRadius: BorderRadius.circular(dpi.radius(12)),
                      border: Border.all(color: MangoThemeFactory.borderColor(context)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                (entry.description != null && entry.description!.trim().isNotEmpty)
                                    ? entry.description!.trim()
                                    : 'Sin descripción',
                                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                      fontWeight: FontWeight.w600,
                                      fontStyle: (entry.description == null || entry.description!.trim().isEmpty)
                                          ? FontStyle.italic
                                          : null,
                                    ),
                              ),
                              if (entry.createdAt != null) ...[
                                SizedBox(height: dpi.space(2)),
                                Text(MangoFormatters.dateTime(entry.createdAt!), style: Theme.of(context).textTheme.bodySmall),
                              ],
                            ],
                          ),
                        ),
                        SizedBox(width: dpi.space(10)),
                        Text(
                          MangoFormatters.currency(entry.amount),
                          style: TextStyle(fontSize: dpi.font(14), fontWeight: FontWeight.w800, color: color),
                        ),
                      ],
                    ),
                  ),
                ],
              SizedBox(height: dpi.space(8)),
            ],
          ),
        );
      },
    );
  }
}

/// Compact info sheet used to explain a number (e.g. the difference) or show a
/// small per-method breakdown.
class _InfoSheet extends StatelessWidget {
  const _InfoSheet({
    required this.title,
    required this.icon,
    required this.color,
    required this.rows,
    this.footnote,
  });

  final String title;
  final IconData icon;
  final Color color;
  final List<_BreakdownRow> rows;
  final String? footnote;

  @override
  Widget build(BuildContext context) {
    final dpi = DpiScale.of(context);
    return Container(
      decoration: BoxDecoration(
        color: MangoThemeFactory.cardColor(context),
        borderRadius: BorderRadius.vertical(top: Radius.circular(dpi.radius(24))),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.all(dpi.space(18)),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: dpi.scale(42),
                  height: dpi.scale(4),
                  decoration: BoxDecoration(color: MangoThemeFactory.borderColor(context), borderRadius: BorderRadius.circular(999)),
                ),
              ),
              SizedBox(height: dpi.space(18)),
              Row(
                children: [
                  Container(
                    width: dpi.scale(40),
                    height: dpi.scale(40),
                    decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(dpi.radius(12))),
                    child: Icon(icon, color: color, size: dpi.icon(20)),
                  ),
                  SizedBox(width: dpi.space(12)),
                  Expanded(child: Text(title, style: Theme.of(context).textTheme.titleLarge)),
                ],
              ),
              SizedBox(height: dpi.space(16)),
              _BreakdownCard(rows: rows),
              if (footnote != null) ...[
                SizedBox(height: dpi.space(12)),
                Text(footnote!, style: Theme.of(context).textTheme.bodySmall),
              ],
              SizedBox(height: dpi.space(8)),
            ],
          ),
        ),
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.icon,
    required this.color,
    required this.label,
    required this.value,
    this.subtitle,
    this.valueColor,
    this.onTap,
    this.count,
  });
  final IconData icon;
  final Color color;
  final String label;
  final String value;
  final String? subtitle;
  final Color? valueColor;
  final VoidCallback? onTap;

  /// When set (and > 0) and [onTap] is provided, shows a small "N detalles" hint.
  final int? count;

  @override
  Widget build(BuildContext context) {
    final dpi = DpiScale.of(context);
    final interactive = onTap != null;
    final hasCount = (count ?? 0) > 0;

    final card = Container(
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
                Text(
                  value,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: valueColor,
                      ),
                ),
                if (subtitle != null) ...[
                  SizedBox(height: dpi.space(2)),
                  Text(subtitle!, style: Theme.of(context).textTheme.bodySmall),
                ],
              ],
            ),
          ),
          if (interactive) ...[
            SizedBox(width: dpi.space(8)),
            if (hasCount)
              Container(
                padding: EdgeInsets.symmetric(horizontal: dpi.space(8), vertical: dpi.space(3)),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '${count!}',
                  style: TextStyle(fontSize: dpi.font(11), fontWeight: FontWeight.w800, color: color),
                ),
              ),
            SizedBox(width: dpi.space(4)),
            Icon(Icons.chevron_right_rounded, size: dpi.icon(20), color: MangoThemeFactory.mutedText(context)),
          ],
        ],
      ),
    );

    if (!interactive) return card;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(dpi.radius(16)),
        child: card,
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
class TopProductsDetailView extends ConsumerStatefulWidget {
  const TopProductsDetailView({super.key, required this.summary});

  final DashboardSummary summary;

  @override
  ConsumerState<TopProductsDetailView> createState() => _TopProductsDetailViewState();
}

class _TopProductsDetailViewState extends ConsumerState<TopProductsDetailView> {
  String _query = '';
  _SortMode _sort = _SortMode.amount;
  late DateTime _start;
  late DateTime _end;
  late String _periodLabel;
  DetailPeriod _period = DetailPeriod.initial;
  DateTimeRange? _customRange;
  late List<TopProduct> _products;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _start = widget.summary.periodStart ??
        DateTime.now().subtract(const Duration(days: 1));
    _end = widget.summary.periodEnd ?? DateTime.now();
    _periodLabel = periodLabelFor(widget.summary.filter);
    _products = widget.summary.topProducts;
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await ref
          .read(dashboardDataServiceProvider)
          .loadTopProductsForPeriod(
            businessId: widget.summary.profile.businessId,
            start: _start,
            end: _end,
          );
      if (!mounted) return;
      setState(() {
        _products = result;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'No se pudo cargar los productos.';
      });
    }
  }

  void _applyPeriod(DetailPeriod period) {
    if (period == DetailPeriod.initial) {
      setState(() {
        _period = DetailPeriod.initial;
        _start = widget.summary.periodStart ??
            DateTime.now().subtract(const Duration(days: 1));
        _end = widget.summary.periodEnd ?? DateTime.now();
        _periodLabel = periodLabelFor(widget.summary.filter);
      });
      _reload();
      return;
    }
    final range = rangeForDetailPeriod(period, DateTime.now());
    if (range == null) return;
    setState(() {
      _period = period;
      _start = range.start;
      _end = range.end;
      _periodLabel = labelForDetailPeriod(period);
    });
    _reload();
  }

  Future<void> _pickCustomRange() async {
    final now = DateTime.now();
    final firstDate = DateTime(now.year - 3);
    final lastDate = DateTime(now.year, now.month, now.day);
    // Preset periods can end in the future (e.g. "este mes"); clamp the seed
    // into the picker bounds so its assertions hold.
    final seed = clampInitialDateRange(
      start: _customRange?.start ?? _start,
      end: _customRange?.end ?? _end.subtract(const Duration(days: 1)),
      firstDate: firstDate,
      lastDate: lastDate,
    );
    final picked = await showDateRangePicker(
      context: context,
      firstDate: firstDate,
      lastDate: lastDate,
      initialDateRange: seed,
    );
    if (picked == null || !mounted) return;
    final start = DateTime(picked.start.year, picked.start.month, picked.start.day);
    final end = DateTime(picked.end.year, picked.end.month, picked.end.day)
        .add(const Duration(days: 1));
    setState(() {
      _period = DetailPeriod.custom;
      _customRange = picked;
      _start = start;
      _end = end;
      _periodLabel = labelForDetailPeriod(DetailPeriod.custom, customRange: picked);
    });
    _reload();
  }

  List<TopProduct> _applyFilterAndSort(List<TopProduct> source) {
    final q = _query.trim().toLowerCase();
    final filtered = q.isEmpty
        ? List<TopProduct>.from(source)
        : source.where((p) => p.label.toLowerCase().contains(q)).toList();
    switch (_sort) {
      case _SortMode.amount:
        filtered.sort((a, b) => b.amount.compareTo(a.amount));
        break;
      case _SortMode.quantity:
        filtered.sort((a, b) => b.quantity.compareTo(a.quantity));
        break;
      case _SortMode.name:
        filtered
            .sort((a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()));
        break;
    }
    return filtered;
  }

  List<List<String>> _rowsForExport() {
    return _applyFilterAndSort(_products)
        .map((p) => [
              p.label,
              p.quantity.toStringAsFixed(p.quantity.truncateToDouble() == p.quantity ? 0 : 2),
              p.amount.toStringAsFixed(2),
            ])
        .toList();
  }

  Future<void> _exportCsv() async {
    await ReportExportService.exportCsv(
      filename: 'productos_${_periodLabel.replaceAll(' ', '_')}',
      headers: const ['Producto', 'Unidades', 'Ingreso'],
      rows: _rowsForExport(),
      subject: 'Productos más vendidos · $_periodLabel',
    );
  }

  Future<void> _exportPdf() async {
    await ReportExportService.exportPdf(
      filename: 'productos_${_periodLabel.replaceAll(' ', '_')}',
      title: 'Productos más vendidos',
      subtitle: 'Periodo: $_periodLabel',
      headers: const ['Producto', 'Unidades', 'Ingreso'],
      rows: _rowsForExport(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dpi = DpiScale.of(context);
    final filtered = _applyFilterAndSort(_products);

    final maxAmount = _products.isEmpty
        ? 0.0
        : _products.map((p) => p.amount).reduce((a, b) => a > b ? a : b);
    final totalAmount = _products.fold<double>(0, (sum, p) => sum + p.amount);
    final totalUnits = _products.fold<double>(0, (sum, p) => sum + p.quantity);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Productos'),
        centerTitle: false,
        actions: [
          ExportMenuButton(
            enabled: _products.isNotEmpty,
            onExportCsv: _exportCsv,
            onExportPdf: _exportPdf,
          ),
        ],
      ),
      body: Column(
        children: [
          _TopProductsHeader(
            totalProducts: _products.length,
            totalAmount: totalAmount,
            totalUnits: totalUnits,
            filterLabel: _periodLabel,
          ),
          PeriodFilterBar(
            selected: _period,
            customRange: _customRange,
            initialLabel: periodLabelFor(widget.summary.filter),
            onSelected: _applyPeriod,
            onPickCustom: _pickCustomRange,
            accent: MangoThemeFactory.mango,
          ),
          SizedBox(height: dpi.space(10)),
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
            child: Builder(builder: (context) {
              if (_loading) {
                return const Center(child: CircularProgressIndicator());
              }
              if (_error != null) {
                return Center(
                  child: Padding(
                    padding: EdgeInsets.all(dpi.space(20)),
                    child: Text(_error!,
                        style: TextStyle(color: MangoThemeFactory.danger),
                        textAlign: TextAlign.center),
                  ),
                );
              }
              if (filtered.isEmpty) {
                return Center(
                  child: Text(
                    _query.isEmpty
                        ? 'Sin productos en este periodo.'
                        : 'Sin resultados para "$_query".',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                );
              }
              return ListView.separated(
                padding: EdgeInsets.fromLTRB(
                    dpi.space(16),
                    dpi.space(8),
                    dpi.space(16),
                    dpi.space(16) + MediaQuery.of(context).padding.bottom),
                itemCount: filtered.length,
                separatorBuilder: (_, _) => SizedBox(height: dpi.space(10)),
                itemBuilder: (context, index) {
                  final p = filtered[index];
                  return _TopProductCard(
                    product: p,
                    rank: _products.indexOf(p) + 1,
                    maxAmount: maxAmount,
                    totalAmount: totalAmount,
                  );
                },
              );
            }),
          ),
        ],
      ),
    );
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
            label: cashDifference == 0 ? 'Dif. efectivo' : (cashDifference > 0 ? 'Sobrante efectivo' : 'Faltante efectivo'),
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
          const _ReceiptSectionTitle('RESULTADO DEL CIERRE'),
          _ReceiptRow(label: 'Total esperado', value: MangoFormatters.currency(closing.expectedTotal)),
          _ReceiptRow(label: 'Total reportado', value: MangoFormatters.currency(closing.reportedTotal)),
          SizedBox(height: dpi.space(4)),
          Builder(
            builder: (_) {
              final net = closing.netDifference;
              return _ReceiptRow(
                label: net == 0 ? 'Diferencia neta' : (net > 0 ? 'Sobrante (neto)' : 'Faltante (neto)'),
                value: MangoFormatters.currency(net.abs()),
                valueColor: net == 0
                    ? null
                    : net > 0
                        ? MangoThemeFactory.success
                        : MangoThemeFactory.danger,
                emphasis: true,
              );
            },
          ),
          SizedBox(height: dpi.space(4)),
          _ReceiptRow(label: 'Dif. efectivo', value: _signedCurrency(closing.cashDifference), valueColor: _diffColor(context, closing.cashDifference)),
          _ReceiptRow(label: 'Dif. tarjeta', value: _signedCurrency(closing.cardDifference), valueColor: _diffColor(context, closing.cardDifference)),
          _ReceiptRow(label: 'Dif. transferencia', value: _signedCurrency(closing.transferDifference), valueColor: _diffColor(context, closing.transferDifference)),
          if (!closing.hasReportedBreakdown)
            Padding(
              padding: EdgeInsets.only(top: dpi.space(4)),
              child: Text(
                'Sin desglose reportado por método; la diferencia neta refleja solo el efectivo.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: MangoThemeFactory.mutedText(context)),
              ),
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
