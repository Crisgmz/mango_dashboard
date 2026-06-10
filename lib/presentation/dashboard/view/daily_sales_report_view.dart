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

/// "Ventas por día" — for a date range, the gross sales of each day, the range
/// total, and the tax breakdown (venta sin impuestos · ITBIS · propina · total
/// general). Based on paid orders so the figures reconcile.
class DailySalesReportView extends ConsumerStatefulWidget {
  const DailySalesReportView({
    super.key,
    required this.start,
    required this.end,
    this.periodLabel,
  });

  final DateTime start;
  final DateTime end;
  final String? periodLabel;

  @override
  ConsumerState<DailySalesReportView> createState() => _DailySalesReportViewState();
}

class _DailySalesReportViewState extends ConsumerState<DailySalesReportView> {
  late Future<DailySalesReport> _future;
  late DateTime _start;
  late DateTime _end;
  late String _periodLabel;
  DetailPeriod _period = DetailPeriod.initial;
  DateTimeRange? _customRange;

  DailySalesReport _loaded = const DailySalesReport();

  @override
  void initState() {
    super.initState();
    _start = widget.start;
    _end = widget.end;
    _periodLabel = widget.periodLabel ?? 'Periodo';
    _future = _load();
  }

  Future<DailySalesReport> _load() async {
    final profile = ref.read(authGateViewModelProvider).profile;
    final businessId = profile?.businessId;
    if (businessId == null) return const DailySalesReport();
    final report = await ref.read(dashboardDataServiceProvider).loadDailySales(
          businessId: businessId,
          start: _start,
          end: _end,
        );
    if (mounted) setState(() => _loaded = report);
    return report;
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

  List<List<String>> _rowsForExport() {
    final rows = _loaded.days
        .map((d) => [
              _dayLabel(d.date),
              d.orderCount.toString(),
              d.total.toStringAsFixed(2),
            ])
        .toList();
    rows.add(['', '', '']);
    rows.add(['Venta sin impuestos', '', _loaded.netTotal.toStringAsFixed(2)]);
    for (final t in _loaded.taxes) {
      rows.add([t.name, '', t.amount.toStringAsFixed(2)]);
    }
    rows.add(['TOTAL GENERAL', _loaded.orderCount.toString(), _loaded.grossTotal.toStringAsFixed(2)]);
    return rows;
  }

  Future<void> _exportCsv() async {
    await ReportExportService.exportCsv(
      filename: 'ventas_por_dia_${_periodLabel.replaceAll(' ', '_')}',
      headers: const ['Fecha / Concepto', 'Órdenes', 'Monto'],
      rows: _rowsForExport(),
      subject: 'Ventas por día · $_periodLabel',
    );
  }

  Future<void> _exportPdf() async {
    await ReportExportService.exportPdf(
      filename: 'ventas_por_dia_${_periodLabel.replaceAll(' ', '_')}',
      title: 'Ventas por día',
      subtitle: 'Periodo: $_periodLabel',
      headers: const ['Fecha / Concepto', 'Órdenes', 'Monto'],
      rows: _rowsForExport(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dpi = DpiScale.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ventas por día'),
        centerTitle: false,
        actions: [
          ExportMenuButton(
            enabled: _loaded.days.isNotEmpty,
            onExportCsv: _exportCsv,
            onExportPdf: _exportPdf,
          ),
        ],
      ),
      body: FutureBuilder<DailySalesReport>(
        future: _future,
        builder: (context, snapshot) {
          final loading = snapshot.connectionState == ConnectionState.waiting;
          final hasError = snapshot.hasError;
          final report = snapshot.data ?? const DailySalesReport();
          final maxDay = report.days.fold<double>(
              0, (m, d) => d.total > m ? d.total : m);

          return Column(
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(dpi.space(16), dpi.space(16), dpi.space(16), 0),
                child: _Header(
                  total: report.grossTotal,
                  days: report.days.length,
                  orders: report.orderCount,
                  periodLabel: _periodLabel,
                ),
              ),
              SizedBox(height: dpi.space(12)),
              PeriodFilterBar(
                selected: _period,
                customRange: _customRange,
                initialLabel: widget.periodLabel,
                onSelected: _applyPeriod,
                onPickCustom: _pickCustomRange,
              ),
              SizedBox(height: dpi.space(10)),
              Expanded(
                child: Builder(builder: (context) {
                  if (loading) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (hasError) {
                    return Center(
                      child: Padding(
                        padding: EdgeInsets.all(dpi.space(20)),
                        child: Text(
                          'No se pudo cargar el reporte.',
                          style: TextStyle(color: MangoThemeFactory.danger),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    );
                  }
                  if (report.days.isEmpty) {
                    return Center(
                      child: Padding(
                        padding: EdgeInsets.all(dpi.space(20)),
                        child: Text(
                          'No hubo ventas en este periodo.',
                          style: Theme.of(context).textTheme.bodySmall,
                          textAlign: TextAlign.center,
                        ),
                      ),
                    );
                  }
                  return ListView(
                    physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
                    padding: EdgeInsets.fromLTRB(dpi.space(16), 0, dpi.space(16),
                        dpi.space(16) + MediaQuery.of(context).padding.bottom),
                    children: [
                      Text(
                        'Venta diaria',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      SizedBox(height: dpi.space(10)),
                      for (final d in report.days) ...[
                        _DayRow(entry: d, maxValue: maxDay),
                        SizedBox(height: dpi.space(8)),
                      ],
                      SizedBox(height: dpi.space(8)),
                      _SummaryCard(report: report),
                    ],
                  );
                }),
              ),
            ],
          );
        },
      ),
    );
  }
}

String _dayLabel(DateTime date) {
  const weekdays = ['Lun', 'Mar', 'Mié', 'Jue', 'Vie', 'Sáb', 'Dom'];
  final wd = weekdays[(date.weekday - 1) % 7];
  final dd = date.day.toString().padLeft(2, '0');
  final mm = date.month.toString().padLeft(2, '0');
  return '$wd $dd/$mm/${date.year}';
}

class _Header extends StatelessWidget {
  const _Header({
    required this.total,
    required this.days,
    required this.orders,
    required this.periodLabel,
  });
  final double total;
  final int days;
  final int orders;
  final String periodLabel;

  @override
  Widget build(BuildContext context) {
    final dpi = DpiScale.of(context);
    return Container(
      padding: EdgeInsets.all(dpi.space(18)),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [MangoThemeFactory.info, MangoThemeFactory.info.withValues(alpha: 0.78)],
        ),
        borderRadius: BorderRadius.circular(dpi.radius(20)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.calendar_month_rounded, color: Colors.white, size: dpi.icon(18)),
              SizedBox(width: dpi.space(6)),
              Text(
                'Ventas por día · $periodLabel',
                style: TextStyle(color: Colors.white, fontSize: dpi.font(12), fontWeight: FontWeight.w600),
              ),
            ],
          ),
          SizedBox(height: dpi.space(10)),
          Text(
            'Total del periodo',
            style: TextStyle(color: Colors.white70, fontSize: dpi.font(11)),
          ),
          SizedBox(height: dpi.space(2)),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              MangoFormatters.currency(total),
              style: TextStyle(color: Colors.white, fontSize: dpi.font(24), fontWeight: FontWeight.w800),
            ),
          ),
          SizedBox(height: dpi.space(10)),
          Row(
            children: [
              Expanded(child: _MiniStat(label: 'Días con venta', value: '$days')),
              Container(width: 1, height: dpi.scale(26), color: Colors.white.withValues(alpha: 0.22)),
              Expanded(child: _MiniStat(label: 'Órdenes', value: MangoFormatters.number(orders))),
            ],
          ),
        ],
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final dpi = DpiScale.of(context);
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: dpi.space(6)),
      child: Column(
        children: [
          Text(label, style: TextStyle(color: Colors.white70, fontSize: dpi.font(10))),
          SizedBox(height: dpi.space(2)),
          Text(value, style: TextStyle(color: Colors.white, fontSize: dpi.font(15), fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}

class _DayRow extends StatelessWidget {
  const _DayRow({required this.entry, required this.maxValue});
  final DailySalesEntry entry;
  final double maxValue;

  @override
  Widget build(BuildContext context) {
    final dpi = DpiScale.of(context);
    final share = maxValue == 0 ? 0.0 : (entry.total / maxValue);
    return Container(
      padding: EdgeInsets.all(dpi.space(14)),
      decoration: BoxDecoration(
        color: MangoThemeFactory.cardColor(context),
        borderRadius: BorderRadius.circular(dpi.radius(14)),
        border: Border.all(color: MangoThemeFactory.borderColor(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _dayLabel(entry.date),
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    SizedBox(height: dpi.space(2)),
                    Text(
                      '${MangoFormatters.number(entry.orderCount)} ${entry.orderCount == 1 ? 'orden' : 'órdenes'}',
                      style: TextStyle(fontSize: dpi.font(11), color: MangoThemeFactory.mutedText(context)),
                    ),
                  ],
                ),
              ),
              SizedBox(width: dpi.space(8)),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  MangoFormatters.currency(entry.total),
                  style: TextStyle(
                    fontSize: dpi.font(14),
                    fontWeight: FontWeight.w800,
                    color: MangoThemeFactory.textColor(context),
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: dpi.space(8)),
          Stack(
            children: [
              Container(
                height: dpi.space(5),
                decoration: BoxDecoration(
                  color: MangoThemeFactory.borderColor(context),
                  borderRadius: BorderRadius.circular(dpi.radius(3)),
                ),
              ),
              FractionallySizedBox(
                widthFactor: share.clamp(0.0, 1.0),
                child: Container(
                  height: dpi.space(5),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [MangoThemeFactory.info, MangoThemeFactory.info.withValues(alpha: 0.7)],
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

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.report});
  final DailySalesReport report;

  @override
  Widget build(BuildContext context) {
    final dpi = DpiScale.of(context);
    return Container(
      padding: EdgeInsets.all(dpi.space(16)),
      decoration: BoxDecoration(
        color: MangoThemeFactory.cardColor(context),
        borderRadius: BorderRadius.circular(dpi.radius(16)),
        border: Border.all(color: MangoThemeFactory.borderColor(context)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(Icons.summarize_rounded, color: MangoThemeFactory.info, size: dpi.icon(18)),
              SizedBox(width: dpi.space(8)),
              Text(
                'Resumen del periodo',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
              ),
            ],
          ),
          SizedBox(height: dpi.space(10)),
          _row(context, 'Total ventas', report.grossTotal, bold: true),
          const _ThinDivider(),
          _row(context, 'Venta sin impuestos', report.netTotal),
          if (report.taxes.isEmpty)
            _row(context, 'Impuestos', 0)
          else
            for (final t in report.taxes) _row(context, _taxLabel(t), t.amount),
          const _ThinDivider(),
          _row(context, 'Total general de ventas', report.grossTotal, bold: true, accent: true),
        ],
      ),
    );
  }

  /// Tax name + its rate, taken from the data (not hardcoded). A rate of 0.18
  /// is shown as "ITBIS (18%)"; when the rate is unknown, just the name.
  String _taxLabel(TaxLineTotal t) {
    final r = t.rate;
    if (r == null || r <= 0) return t.name;
    final pct = r < 1 ? r * 100 : r; // accept either 0.18 or 18
    final pctStr = pct == pct.roundToDouble()
        ? pct.toStringAsFixed(0)
        : pct.toStringAsFixed(2);
    return '${t.name} ($pctStr%)';
  }

  Widget _row(BuildContext context, String label, double value,
      {bool bold = false, bool accent = false}) {
    final dpi = DpiScale.of(context);
    return Padding(
      padding: EdgeInsets.symmetric(vertical: dpi.space(7)),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
                    color: bold ? null : MangoThemeFactory.mutedText(context),
                  ),
            ),
          ),
          SizedBox(width: dpi.space(10)),
          Text(
            MangoFormatters.currency(value),
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: bold ? FontWeight.w800 : FontWeight.w700,
                  color: accent ? MangoThemeFactory.info : MangoThemeFactory.textColor(context),
                ),
          ),
        ],
      ),
    );
  }
}

class _ThinDivider extends StatelessWidget {
  const _ThinDivider();
  @override
  Widget build(BuildContext context) {
    final dpi = DpiScale.of(context);
    return Padding(
      padding: EdgeInsets.symmetric(vertical: dpi.space(4)),
      child: Divider(height: 1, color: MangoThemeFactory.borderColor(context)),
    );
  }
}
