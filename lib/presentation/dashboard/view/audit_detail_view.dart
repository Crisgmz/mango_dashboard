import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/di/providers.dart';
import '../../../core/formatters/mango_formatters.dart';
import '../../../core/responsive/dpi_scale.dart';
import '../../../data/export/report_export_service.dart';
import '../../../domain/dashboard/dashboard_models.dart';
import '../../auth/viewmodel/auth_gate_view_model.dart';
import '../../theme/theme_data_factory.dart';
import '../widgets/period_filter_bar.dart';

/// Loss-prevention view: lists voided items, cancelled payments, and
/// discounted orders for a period in three tabs.
class AuditDetailView extends ConsumerStatefulWidget {
  const AuditDetailView({
    super.key,
    required this.start,
    required this.end,
    this.periodLabel,
  });

  final DateTime start;
  final DateTime end;
  final String? periodLabel;

  @override
  ConsumerState<AuditDetailView> createState() => _AuditDetailViewState();
}

class _AuditDetailViewState extends ConsumerState<AuditDetailView> {
  late Future<({AuditSummary summary, AuditDetail detail})> _future;
  late DateTime _start;
  late DateTime _end;
  late String _periodLabel;
  DetailPeriod _period = DetailPeriod.initial;
  DateTimeRange? _customRange;
  String _query = '';
  AuditDetail _loaded = const AuditDetail();

  @override
  void initState() {
    super.initState();
    _start = widget.start;
    _end = widget.end;
    _periodLabel = widget.periodLabel ?? 'Periodo';
    _future = _load();
  }

  Future<({AuditSummary summary, AuditDetail detail})> _load() async {
    final profile = ref.read(authGateViewModelProvider).profile;
    final businessId = profile?.businessId;
    if (businessId == null) {
      return (
        summary: const AuditSummary(),
        detail: const AuditDetail(),
      );
    }
    final result = await ref.read(dashboardDataServiceProvider).loadAuditDetail(
          businessId: businessId,
          start: _start,
          end: _end,
        );
    if (mounted) setState(() => _loaded = result.detail);
    return result;
  }

  void _applyPeriod(DetailPeriod period) {
    if (period == DetailPeriod.initial) {
      setState(() {
        _period = DetailPeriod.initial;
        _start = widget.start;
        _end = widget.end;
        _periodLabel = widget.periodLabel ?? 'Periodo';
        _future = _load();
      });
      return;
    }
    final range = rangeForDetailPeriod(period, DateTime.now());
    if (range == null) return;
    setState(() {
      _period = period;
      _start = range.start;
      _end = range.end;
      _periodLabel = labelForDetailPeriod(period);
      _future = _load();
    });
  }

  Future<void> _pickCustomRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 3),
      lastDate: now,
      initialDateRange: _customRange ??
          DateTimeRange(start: _start, end: _end.subtract(const Duration(days: 1))),
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
      _future = _load();
    });
  }

  bool _matchesQuery(String text) {
    if (_query.isEmpty) return true;
    return text.toLowerCase().contains(_query.toLowerCase());
  }

  List<VoidedItem> get _filteredVoids => _loaded.voidedItems
      .where((v) => _matchesQuery(
          '${v.productName} ${v.tableLabel ?? ''} ${v.waiterName ?? ''}'))
      .toList();

  List<CancelledPayment> get _filteredCancellations => _loaded.cancelledPayments
      .where((p) => _matchesQuery(
          '${p.tableLabel ?? ''} ${p.cashierName ?? ''} ${p.methodCode ?? ''}'))
      .toList();

  List<DiscountedOrder> get _filteredDiscounts => _loaded.discountedOrders
      .where((d) => _matchesQuery(
          '${d.tableLabel ?? ''} ${d.customerName ?? ''} ${d.waiterName ?? ''}'))
      .toList();

  List<List<String>> _rowsForExport() {
    final rows = <List<String>>[];
    for (final v in _filteredVoids) {
      rows.add([
        'Void',
        _formatDateTime(v.createdAt),
        '${v.productName} (${v.quantity.toStringAsFixed(0)})',
        v.amount.toStringAsFixed(2),
        [v.tableLabel, if (v.waiterName != null) 'Mesero: ${v.waiterName}']
            .whereType<String>()
            .join(' · '),
      ]);
    }
    for (final p in _filteredCancellations) {
      rows.add([
        p.status == 'void' ? 'Pago anulado' : 'Cancelación',
        _formatDateTime(p.createdAt),
        p.methodCode == null
            ? 'Pago cancelado'
            : 'Pago cancelado (${_methodLabel(p.methodCode!)})',
        p.amount.toStringAsFixed(2),
        [p.tableLabel, if (p.cashierName != null) 'Cajero: ${p.cashierName}']
            .whereType<String>()
            .join(' · '),
      ]);
    }
    for (final d in _filteredDiscounts) {
      rows.add([
        'Descuento',
        _formatDateTime(d.createdAt),
        '${d.tableLabel ?? 'Orden'} (${(d.percent * 100).toStringAsFixed(1)}%)',
        d.discount.toStringAsFixed(2),
        [
          'Total ${MangoFormatters.currency(d.total)}',
          if (d.customerName != null && d.customerName!.trim().isNotEmpty)
            d.customerName!,
          if (d.waiterName != null) 'Mesero: ${d.waiterName}',
        ].join(' · '),
      ]);
    }
    return rows;
  }

  Future<void> _exportCsv() async {
    await ReportExportService.exportCsv(
      filename: 'auditoria_${_periodLabel.replaceAll(' ', '_')}',
      headers: const ['Tipo', 'Fecha', 'Detalle', 'Monto', 'Referencias'],
      rows: _rowsForExport(),
      subject: 'Reporte de auditoría · $_periodLabel',
    );
  }

  Future<void> _exportPdf() async {
    await ReportExportService.exportPdf(
      filename: 'auditoria_${_periodLabel.replaceAll(' ', '_')}',
      title: 'Auditoría',
      subtitle: 'Periodo: $_periodLabel',
      headers: const ['Tipo', 'Fecha', 'Detalle', 'Monto', 'Referencias'],
      rows: _rowsForExport(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dpi = DpiScale.of(context);
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Auditoría'),
          centerTitle: false,
          actions: [
            ExportMenuButton(
              enabled: _loaded.voidedItems.isNotEmpty ||
                  _loaded.cancelledPayments.isNotEmpty ||
                  _loaded.discountedOrders.isNotEmpty,
              onExportCsv: _exportCsv,
              onExportPdf: _exportPdf,
            ),
          ],
          bottom: const TabBar(
            indicatorColor: MangoThemeFactory.mango,
            labelColor: MangoThemeFactory.mango,
            tabs: [
              Tab(icon: Icon(Icons.block_rounded), text: 'Voids'),
              Tab(icon: Icon(Icons.cancel_rounded), text: 'Cancelaciones'),
              Tab(icon: Icon(Icons.discount_rounded), text: 'Descuentos'),
            ],
          ),
        ),
        body: FutureBuilder<({AuditSummary summary, AuditDetail detail})>(
          future: _future,
          builder: (context, snapshot) {
            final loading = snapshot.connectionState == ConnectionState.waiting;
            if (snapshot.hasError) {
              return Center(
                child: Padding(
                  padding: EdgeInsets.all(dpi.space(20)),
                  child: Text(
                    'No se pudo cargar la auditoría.',
                    style: TextStyle(color: MangoThemeFactory.danger),
                    textAlign: TextAlign.center,
                  ),
                ),
              );
            }

            final summary = snapshot.data?.summary ?? const AuditSummary();

            return Column(
              children: [
                _AuditHeader(summary: summary, periodLabel: _periodLabel),
                SizedBox(height: dpi.space(8)),
                PeriodFilterBar(
                  selected: _period,
                  customRange: _customRange,
                  initialLabel: widget.periodLabel,
                  onSelected: _applyPeriod,
                  onPickCustom: _pickCustomRange,
                  accent: MangoThemeFactory.danger,
                ),
                SizedBox(height: dpi.space(10)),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: dpi.space(16)),
                  child: TextField(
                    onChanged: (v) => setState(() => _query = v),
                    decoration: InputDecoration(
                      hintText: 'Buscar producto, mesa, cajero…',
                      prefixIcon: const Icon(Icons.search_rounded),
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(
                          horizontal: dpi.space(12), vertical: dpi.space(12)),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(dpi.radius(12))),
                    ),
                  ),
                ),
                SizedBox(height: dpi.space(8)),
                Expanded(
                  child: loading
                      ? const Center(child: CircularProgressIndicator())
                      : TabBarView(
                          children: [
                            _VoidedItemsTab(items: _filteredVoids),
                            _CancelledPaymentsTab(items: _filteredCancellations),
                            _DiscountedOrdersTab(items: _filteredDiscounts),
                          ],
                        ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

String _methodLabel(String code) {
  switch (code) {
    case 'cash':
      return 'Efectivo';
    case 'card':
      return 'Tarjeta';
    case 'transfer':
      return 'Transferencia';
    default:
      return code;
  }
}

String _formatDateTime(DateTime t) {
  final h = t.hour.toString().padLeft(2, '0');
  final m = t.minute.toString().padLeft(2, '0');
  return '${t.day}/${t.month}/${t.year} $h:$m';
}

class _AuditHeader extends StatelessWidget {
  const _AuditHeader({required this.summary, this.periodLabel});

  final AuditSummary summary;
  final String? periodLabel;

  @override
  Widget build(BuildContext context) {
    final dpi = DpiScale.of(context);
    return Container(
      margin: EdgeInsets.fromLTRB(dpi.space(16), dpi.space(16), dpi.space(16), dpi.space(8)),
      padding: EdgeInsets.all(dpi.space(18)),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [MangoThemeFactory.danger, MangoThemeFactory.danger.withValues(alpha: 0.78)],
        ),
        borderRadius: BorderRadius.circular(dpi.radius(20)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.white, size: dpi.icon(18)),
              SizedBox(width: dpi.space(6)),
              Text(
                periodLabel == null ? 'Periodo' : 'Auditoría · $periodLabel',
                style: TextStyle(color: Colors.white, fontSize: dpi.font(12), fontWeight: FontWeight.w600),
              ),
            ],
          ),
          SizedBox(height: dpi.space(10)),
          Text(
            'Pérdida total registrada',
            style: TextStyle(color: Colors.white70, fontSize: dpi.font(11)),
          ),
          SizedBox(height: dpi.space(2)),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              MangoFormatters.currency(summary.totalLoss),
              style: TextStyle(color: Colors.white, fontSize: dpi.font(24), fontWeight: FontWeight.w800),
            ),
          ),
          SizedBox(height: dpi.space(10)),
          Row(
            children: [
              Expanded(
                child: _MiniStat(
                  label: 'Voids',
                  value: '${summary.voidedItemsCount}',
                  amount: MangoFormatters.currency(summary.voidedAmount),
                ),
              ),
              _verticalDivider(dpi),
              Expanded(
                child: _MiniStat(
                  label: 'Cancelaciones',
                  value: '${summary.cancelledPaymentsCount}',
                  amount: MangoFormatters.currency(summary.cancelledAmount),
                ),
              ),
              _verticalDivider(dpi),
              Expanded(
                child: _MiniStat(
                  label: 'Descuentos',
                  value: '${summary.discountsAppliedCount}',
                  amount: MangoFormatters.currency(summary.discountsAmount),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _verticalDivider(DpiScale dpi) => Container(
        width: 1,
        height: dpi.scale(28),
        color: Colors.white.withValues(alpha: 0.22),
      );
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({required this.label, required this.value, required this.amount});
  final String label;
  final String value;
  final String amount;

  @override
  Widget build(BuildContext context) {
    final dpi = DpiScale.of(context);
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: dpi.space(4)),
      child: Column(
        children: [
          Text(label, style: TextStyle(color: Colors.white70, fontSize: dpi.font(10))),
          SizedBox(height: dpi.space(2)),
          Text(
            value,
            style: TextStyle(
              color: Colors.white,
              fontSize: dpi.font(15),
              fontWeight: FontWeight.w800,
            ),
          ),
          SizedBox(height: dpi.space(2)),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              amount,
              style: TextStyle(color: Colors.white70, fontSize: dpi.font(10)),
            ),
          ),
        ],
      ),
    );
  }
}

class _VoidedItemsTab extends StatelessWidget {
  const _VoidedItemsTab({required this.items});
  final List<VoidedItem> items;

  @override
  Widget build(BuildContext context) {
    final dpi = DpiScale.of(context);
    if (items.isEmpty) {
      return _EmptyTab(message: 'Sin items anulados en este periodo.');
    }
    return ListView.separated(
      padding: EdgeInsets.fromLTRB(
          dpi.space(16), dpi.space(8), dpi.space(16), dpi.space(16) + MediaQuery.of(context).padding.bottom),
      itemCount: items.length,
      separatorBuilder: (_, _) => SizedBox(height: dpi.space(8)),
      itemBuilder: (context, index) => _AuditTile(
        accent: MangoThemeFactory.warning,
        icon: Icons.block_rounded,
        title: items[index].productName,
        amount: items[index].amount,
        subtitleParts: _voidSubtitle(items[index]),
      ),
    );
  }

  static List<String> _voidSubtitle(VoidedItem v) {
    final parts = <String>[];
    parts.add('${v.quantity.toStringAsFixed(0)} ${v.quantity == 1 ? 'unidad' : 'unidades'}');
    if (v.tableLabel != null) parts.add(v.tableLabel!);
    if (v.waiterName != null) parts.add('Mesero: ${v.waiterName}');
    parts.add(_formatTime(v.createdAt));
    return parts;
  }
}

class _CancelledPaymentsTab extends StatelessWidget {
  const _CancelledPaymentsTab({required this.items});
  final List<CancelledPayment> items;

  @override
  Widget build(BuildContext context) {
    final dpi = DpiScale.of(context);
    if (items.isEmpty) {
      return _EmptyTab(message: 'Sin pagos cancelados en este periodo.');
    }
    return ListView.separated(
      padding: EdgeInsets.fromLTRB(
          dpi.space(16), dpi.space(8), dpi.space(16), dpi.space(16) + MediaQuery.of(context).padding.bottom),
      itemCount: items.length,
      separatorBuilder: (_, _) => SizedBox(height: dpi.space(8)),
      itemBuilder: (context, index) => _AuditTile(
        accent: MangoThemeFactory.danger,
        icon: Icons.cancel_rounded,
        title: items[index].status == 'void' ? 'Pago anulado' : 'Pago cancelado',
        amount: items[index].amount,
        subtitleParts: _cancelSubtitle(items[index]),
      ),
    );
  }

  static List<String> _cancelSubtitle(CancelledPayment p) {
    final parts = <String>[];
    if (p.methodCode != null) parts.add(_methodLabel(p.methodCode!));
    if (p.tableLabel != null) parts.add(p.tableLabel!);
    if (p.cashierName != null) parts.add('Cajero: ${p.cashierName}');
    parts.add(_formatTime(p.createdAt));
    return parts;
  }

  static String _methodLabel(String code) {
    switch (code) {
      case 'cash':
        return 'Efectivo';
      case 'card':
        return 'Tarjeta';
      case 'transfer':
        return 'Transferencia';
      default:
        return code;
    }
  }
}

class _DiscountedOrdersTab extends StatelessWidget {
  const _DiscountedOrdersTab({required this.items});
  final List<DiscountedOrder> items;

  @override
  Widget build(BuildContext context) {
    final dpi = DpiScale.of(context);
    if (items.isEmpty) {
      return _EmptyTab(message: 'Sin descuentos aplicados en este periodo.');
    }
    return ListView.separated(
      padding: EdgeInsets.fromLTRB(
          dpi.space(16), dpi.space(8), dpi.space(16), dpi.space(16) + MediaQuery.of(context).padding.bottom),
      itemCount: items.length,
      separatorBuilder: (_, _) => SizedBox(height: dpi.space(8)),
      itemBuilder: (context, index) {
        final d = items[index];
        return _AuditTile(
          accent: MangoThemeFactory.info,
          icon: Icons.discount_rounded,
          title: d.tableLabel ?? 'Orden',
          amount: d.discount,
          amountSuffix: '(${(d.percent * 100).toStringAsFixed(1)}%)',
          subtitleParts: _discountSubtitle(d),
        );
      },
    );
  }

  static List<String> _discountSubtitle(DiscountedOrder d) {
    final parts = <String>[];
    parts.add('Total ${MangoFormatters.currency(d.total)}');
    if (d.customerName != null && d.customerName!.trim().isNotEmpty) {
      parts.add(d.customerName!);
    }
    if (d.waiterName != null) parts.add('Mesero: ${d.waiterName}');
    parts.add(_formatTime(d.createdAt));
    return parts;
  }
}

class _AuditTile extends StatelessWidget {
  const _AuditTile({
    required this.accent,
    required this.icon,
    required this.title,
    required this.amount,
    required this.subtitleParts,
    this.amountSuffix,
  });

  final Color accent;
  final IconData icon;
  final String title;
  final double amount;
  final String? amountSuffix;
  final List<String> subtitleParts;

  @override
  Widget build(BuildContext context) {
    final dpi = DpiScale.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: EdgeInsets.all(dpi.space(14)),
      decoration: BoxDecoration(
        color: MangoThemeFactory.cardColor(context),
        borderRadius: BorderRadius.circular(dpi.radius(14)),
        border: Border.all(color: MangoThemeFactory.borderColor(context)),
      ),
      child: Row(
        children: [
          Container(
            width: dpi.scale(38),
            height: dpi.scale(38),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: isDark ? 0.2 : 0.12),
              borderRadius: BorderRadius.circular(dpi.radius(10)),
            ),
            child: Icon(icon, color: accent, size: dpi.icon(20)),
          ),
          SizedBox(width: dpi.space(12)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                SizedBox(height: dpi.space(2)),
                Text(
                  subtitleParts.join(' · '),
                  style: TextStyle(fontSize: dpi.font(11), color: MangoThemeFactory.mutedText(context)),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          SizedBox(width: dpi.space(8)),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                MangoFormatters.currency(amount),
                style: TextStyle(
                  fontSize: dpi.font(13),
                  fontWeight: FontWeight.w800,
                  color: accent,
                ),
              ),
              if (amountSuffix != null)
                Text(
                  amountSuffix!,
                  style: TextStyle(
                      fontSize: dpi.font(10), color: MangoThemeFactory.mutedText(context)),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _EmptyTab extends StatelessWidget {
  const _EmptyTab({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    final dpi = DpiScale.of(context);
    return Center(
      child: Padding(
        padding: EdgeInsets.all(dpi.space(40)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.shield_outlined, size: dpi.icon(48), color: MangoThemeFactory.success),
            SizedBox(height: dpi.space(12)),
            Text(
              message,
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

String _formatTime(DateTime t) {
  final h = t.hour.toString().padLeft(2, '0');
  final m = t.minute.toString().padLeft(2, '0');
  return '${t.day}/${t.month} $h:$m';
}
