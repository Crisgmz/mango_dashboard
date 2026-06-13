import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/di/providers.dart';
import '../../../core/formatters/mango_formatters.dart';
import '../../../core/responsive/dpi_scale.dart';
import '../../../data/export/report_export_service.dart';
import '../../../domain/dashboard/dashboard_models.dart';
import '../../auth/viewmodel/auth_gate_view_model.dart';
import '../../theme/theme_data_factory.dart';
import '../widgets/growth_chip.dart';

const _monthsEs = [
  'Ene', 'Feb', 'Mar', 'Abr', 'May', 'Jun',
  'Jul', 'Ago', 'Sep', 'Oct', 'Nov', 'Dic',
];
const _weekdaysEs = ['Lun', 'Mar', 'Mié', 'Jue', 'Vie', 'Sáb', 'Dom'];

/// "Tendencia": sales bucketed by week or month with growth vs the previous
/// bucket, plus a weekday×hour heatmap of when sales happen. Lets the owner see
/// whether the business is growing and when its busiest hours are.
class SalesTrendView extends ConsumerStatefulWidget {
  const SalesTrendView({super.key});

  @override
  ConsumerState<SalesTrendView> createState() => _SalesTrendViewState();
}

class _SalesTrendViewState extends ConsumerState<SalesTrendView> {
  static const _bucketsBack = 12;

  TrendGranularity _granularity = TrendGranularity.week;
  late Future<SalesTrendReport> _future;
  SalesTrendReport _loaded = const SalesTrendReport();

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  ({DateTime start, DateTime end}) _range() {
    final now = DateTime.now();
    final end = DateTime(now.year, now.month, now.day).add(const Duration(days: 1));
    if (_granularity == TrendGranularity.month) {
      return (start: DateTime(now.year, now.month - (_bucketsBack - 1), 1), end: end);
    }
    final monday = DateTime(now.year, now.month, now.day)
        .subtract(Duration(days: now.weekday - 1));
    return (start: monday.subtract(Duration(days: (_bucketsBack - 1) * 7)), end: end);
  }

  Future<SalesTrendReport> _load() async {
    final profile = ref.read(authGateViewModelProvider).profile;
    final businessId = profile?.businessId;
    if (businessId == null) return const SalesTrendReport();
    final r = _range();
    final report = await ref.read(dashboardDataServiceProvider).loadSalesTrend(
          businessId: businessId,
          start: r.start,
          end: r.end,
          granularity: _granularity,
        );
    if (mounted) setState(() => _loaded = report);
    return report;
  }

  void _setGranularity(TrendGranularity g) {
    if (g == _granularity) return;
    setState(() {
      _granularity = g;
      _future = _load();
    });
  }

  bool get _isWeek => _granularity == TrendGranularity.week;

  String _bucketLabel(DateTime start) =>
      _isWeek ? '${start.day}/${start.month}' : _monthsEs[start.month - 1];

  List<List<String>> _rowsForExport() {
    final rows = _loaded.buckets
        .map((b) => [
              _isWeek
                  ? 'Semana del ${b.start.day}/${b.start.month}/${b.start.year}'
                  : '${_monthsEs[b.start.month - 1]} ${b.start.year}',
              MangoFormatters.number(b.orderCount),
              MangoFormatters.amount(b.total),
            ])
        .toList();
    rows.add(['', '', '']);
    rows.add(['TOTAL', '', MangoFormatters.amount(_loaded.total)]);
    return rows;
  }

  Future<void> _exportCsv() => ReportExportService.exportCsv(
        filename: 'tendencia_${_isWeek ? 'semanal' : 'mensual'}',
        headers: const ['Periodo', 'Órdenes', 'Monto'],
        rows: _rowsForExport(),
        subject: 'Tendencia de ventas',
      );

  Future<void> _exportPdf() => ReportExportService.exportPdf(
        filename: 'tendencia_${_isWeek ? 'semanal' : 'mensual'}',
        title: 'Tendencia de ventas',
        subtitle: _isWeek ? 'Por semana' : 'Por mes',
        headers: const ['Periodo', 'Órdenes', 'Monto'],
        rows: _rowsForExport(),
      );

  @override
  Widget build(BuildContext context) {
    final dpi = DpiScale.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Tendencia'),
        centerTitle: false,
        actions: [
          ExportMenuButton(
            enabled: _loaded.buckets.any((b) => b.total > 0),
            onExportCsv: _exportCsv,
            onExportPdf: _exportPdf,
          ),
        ],
      ),
      body: FutureBuilder<SalesTrendReport>(
        future: _future,
        builder: (context, snapshot) {
          final loading = snapshot.connectionState == ConnectionState.waiting;
          final report = snapshot.data ?? const SalesTrendReport();
          return ListView(
            physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
            padding: EdgeInsets.fromLTRB(dpi.space(16), dpi.space(16), dpi.space(16),
                dpi.space(16) + MediaQuery.of(context).padding.bottom),
            children: [
              _GranularityToggle(value: _granularity, onChanged: _setGranularity),
              SizedBox(height: dpi.space(14)),
              _Header(report: report, isWeek: _isWeek),
              SizedBox(height: dpi.space(14)),
              if (loading)
                Padding(
                  padding: EdgeInsets.only(top: dpi.space(40)),
                  child: const Center(child: CircularProgressIndicator()),
                )
              else if (snapshot.hasError)
                _Empty(text: 'No se pudo cargar la tendencia.', danger: true)
              else if (!report.buckets.any((b) => b.total > 0))
                _Empty(text: 'No hubo ventas en este periodo.')
              else ...[
                _TrendCard(report: report, bucketLabel: _bucketLabel),
                SizedBox(height: dpi.space(14)),
                _HeatmapCard(cells: report.heat),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _GranularityToggle extends StatelessWidget {
  const _GranularityToggle({required this.value, required this.onChanged});
  final TrendGranularity value;
  final ValueChanged<TrendGranularity> onChanged;

  @override
  Widget build(BuildContext context) {
    final dpi = DpiScale.of(context);
    Widget seg(String label, TrendGranularity g) {
      final selected = value == g;
      return Expanded(
        child: GestureDetector(
          onTap: () => onChanged(g),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: EdgeInsets.symmetric(vertical: dpi.space(9)),
            decoration: BoxDecoration(
              color: selected ? MangoThemeFactory.info : Colors.transparent,
              borderRadius: BorderRadius.circular(dpi.radius(10)),
            ),
            alignment: Alignment.center,
            child: Text(
              label,
              style: TextStyle(
                fontSize: dpi.font(12),
                fontWeight: FontWeight.w700,
                color: selected ? Colors.white : MangoThemeFactory.mutedText(context),
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      padding: EdgeInsets.all(dpi.space(4)),
      decoration: BoxDecoration(
        color: MangoThemeFactory.cardColor(context),
        borderRadius: BorderRadius.circular(dpi.radius(12)),
        border: Border.all(color: MangoThemeFactory.borderColor(context)),
      ),
      child: Row(children: [
        seg('Semanal', TrendGranularity.week),
        seg('Mensual', TrendGranularity.month),
      ]),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.report, required this.isWeek});
  final SalesTrendReport report;
  final bool isWeek;

  @override
  Widget build(BuildContext context) {
    final dpi = DpiScale.of(context);
    final currentLabel = isWeek ? 'Esta semana' : 'Este mes';
    final comparison = isWeek ? 'vs semana anterior' : 'vs mes anterior';
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
              Icon(Icons.show_chart_rounded, color: Colors.white, size: dpi.icon(18)),
              SizedBox(width: dpi.space(6)),
              Text(
                '$currentLabel · en curso',
                style: TextStyle(
                    color: Colors.white, fontSize: dpi.font(12), fontWeight: FontWeight.w600),
              ),
            ],
          ),
          SizedBox(height: dpi.space(10)),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              MangoFormatters.currency(report.currentTotal),
              style: TextStyle(
                  color: Colors.white, fontSize: dpi.font(26), fontWeight: FontWeight.w800),
            ),
          ),
          SizedBox(height: dpi.space(8)),
          Row(
            children: [
              GrowthChip(current: report.currentTotal, previous: report.previousTotal),
              SizedBox(width: dpi.space(8)),
              Flexible(
                child: Text(
                  comparison,
                  style: TextStyle(color: Colors.white70, fontSize: dpi.font(11)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TrendCard extends StatelessWidget {
  const _TrendCard({required this.report, required this.bucketLabel});
  final SalesTrendReport report;
  final String Function(DateTime) bucketLabel;

  @override
  Widget build(BuildContext context) {
    final dpi = DpiScale.of(context);
    final buckets = report.buckets;
    final maxY = buckets.fold<double>(0, (m, b) => b.total > m ? b.total : m);
    final step = buckets.length > 8 ? 2 : 1;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(dpi.space(16)),
      decoration: BoxDecoration(
        color: MangoThemeFactory.cardColor(context),
        borderRadius: BorderRadius.circular(dpi.radius(16)),
        border: Border.all(color: MangoThemeFactory.borderColor(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            report.granularity == TrendGranularity.week
                ? 'Ventas por semana'
                : 'Ventas por mes',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
          ),
          SizedBox(height: dpi.space(16)),
          SizedBox(
            height: dpi.scale(200),
            child: BarChart(
              BarChartData(
                alignment: BarChartAlignment.spaceAround,
                maxY: (maxY <= 0 ? 1 : maxY) * 1.18,
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: maxY > 0 ? maxY / 4 : 1,
                  getDrawingHorizontalLine: (_) =>
                      FlLine(color: MangoThemeFactory.borderColor(context), strokeWidth: 1),
                ),
                borderData: FlBorderData(show: false),
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: dpi.scale(44),
                      getTitlesWidget: (value, _) => Text(
                        _shortCurrency(value),
                        style: TextStyle(
                            fontSize: dpi.font(9), color: MangoThemeFactory.mutedText(context)),
                      ),
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: dpi.scale(22),
                      getTitlesWidget: (value, _) {
                        final i = value.toInt();
                        if (i < 0 || i >= buckets.length || i % step != 0) {
                          return const SizedBox.shrink();
                        }
                        return Padding(
                          padding: EdgeInsets.only(top: dpi.space(4)),
                          child: Text(
                            bucketLabel(buckets[i].start),
                            style: TextStyle(
                                fontSize: dpi.font(9),
                                color: MangoThemeFactory.mutedText(context)),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                barTouchData: BarTouchData(
                  touchTooltipData: BarTouchTooltipData(
                    getTooltipColor: (_) =>
                        Theme.of(context).brightness == Brightness.dark
                            ? const Color(0xFF2B3138)
                            : Colors.white,
                    getTooltipItem: (group, groupIdx, rod, rodIdx) => BarTooltipItem(
                      MangoFormatters.currency(rod.toY),
                      TextStyle(
                        color: MangoThemeFactory.info,
                        fontWeight: FontWeight.w700,
                        fontSize: dpi.font(12),
                      ),
                    ),
                  ),
                ),
                barGroups: [
                  for (var i = 0; i < buckets.length; i++)
                    BarChartGroupData(x: i, barRods: [
                      BarChartRodData(
                        toY: buckets[i].total,
                        width: dpi.scale(buckets.length > 8 ? 10 : 16),
                        borderRadius: BorderRadius.vertical(top: Radius.circular(dpi.radius(4))),
                        // Highlight the current (last) bucket in mango.
                        color: i == buckets.length - 1
                            ? MangoThemeFactory.mango
                            : MangoThemeFactory.info,
                      ),
                    ]),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HeatmapCard extends StatelessWidget {
  const _HeatmapCard({required this.cells});
  final List<HeatCell> cells;

  @override
  Widget build(BuildContext context) {
    final dpi = DpiScale.of(context);

    final byKey = <int, double>{for (final c in cells) c.weekday * 100 + c.hour: c.total};
    final withData = cells.where((c) => c.total > 0).toList();
    final maxTotal = withData.fold<double>(0, (m, c) => c.total > m ? c.total : m);

    Widget card(Widget child) => Container(
          width: double.infinity,
          padding: EdgeInsets.all(dpi.space(16)),
          decoration: BoxDecoration(
            color: MangoThemeFactory.cardColor(context),
            borderRadius: BorderRadius.circular(dpi.radius(16)),
            border: Border.all(color: MangoThemeFactory.borderColor(context)),
          ),
          child: child,
        );

    final header = Row(
      children: [
        Icon(Icons.grid_on_rounded, color: MangoThemeFactory.mango, size: dpi.icon(18)),
        SizedBox(width: dpi.space(8)),
        Text('¿Cuándo se vende más?',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
      ],
    );

    if (withData.isEmpty || maxTotal <= 0) {
      return card(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        header,
        SizedBox(height: dpi.space(12)),
        Text('Sin datos suficientes para el mapa de calor.',
            style: Theme.of(context).textTheme.bodySmall),
      ]));
    }

    final minHour = withData.map((c) => c.hour).reduce((a, b) => a < b ? a : b);
    final maxHour = withData.map((c) => c.hour).reduce((a, b) => a > b ? a : b);
    final hours = [for (var h = minHour; h <= maxHour; h++) h];
    final cell = dpi.scale(18);
    final gap = dpi.scale(3);

    Color cellColor(double total) {
      final t = (total / maxTotal).clamp(0.0, 1.0);
      if (total <= 0) return MangoThemeFactory.mango.withValues(alpha: 0.05);
      return MangoThemeFactory.mango.withValues(alpha: 0.15 + 0.80 * t);
    }

    final grid = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Hour axis labels (every 3 hours to avoid clutter).
        Padding(
          padding: EdgeInsets.only(left: dpi.scale(34), bottom: gap),
          child: Row(
            children: [
              for (final h in hours)
                Container(
                  width: cell,
                  margin: EdgeInsets.only(right: gap),
                  alignment: Alignment.center,
                  child: (h - minHour) % 3 == 0
                      ? Text(_hourLabel(h),
                          style: TextStyle(
                              fontSize: dpi.font(8),
                              color: MangoThemeFactory.mutedText(context)))
                      : const SizedBox.shrink(),
                ),
            ],
          ),
        ),
        for (var wd = 1; wd <= 7; wd++)
          Padding(
            padding: EdgeInsets.only(bottom: gap),
            child: Row(
              children: [
                SizedBox(
                  width: dpi.scale(34),
                  child: Text(_weekdaysEs[wd - 1],
                      style: TextStyle(
                          fontSize: dpi.font(9),
                          color: MangoThemeFactory.mutedText(context))),
                ),
                for (final h in hours)
                  Tooltip(
                    message:
                        '${_weekdaysEs[wd - 1]} ${_hourLabel(h)} · ${MangoFormatters.currency(byKey[wd * 100 + h] ?? 0)}',
                    waitDuration: const Duration(milliseconds: 250),
                    child: Container(
                      width: cell,
                      height: cell,
                      margin: EdgeInsets.only(right: gap),
                      decoration: BoxDecoration(
                        color: cellColor(byKey[wd * 100 + h] ?? 0),
                        borderRadius: BorderRadius.circular(dpi.radius(3)),
                        border: (byKey[wd * 100 + h] ?? 0) == maxTotal
                            ? Border.all(color: MangoThemeFactory.mangoDeep, width: 1.5)
                            : null,
                      ),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );

    return card(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      header,
      SizedBox(height: dpi.space(4)),
      Text('Intensidad de ventas por día de la semana y hora',
          style: TextStyle(
              fontSize: dpi.font(11), color: MangoThemeFactory.mutedText(context))),
      SizedBox(height: dpi.space(14)),
      SingleChildScrollView(scrollDirection: Axis.horizontal, child: grid),
    ]));
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.text, this.danger = false});
  final String text;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final dpi = DpiScale.of(context);
    return Padding(
      padding: EdgeInsets.only(top: dpi.space(40)),
      child: Center(
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: danger
              ? TextStyle(color: MangoThemeFactory.danger)
              : Theme.of(context).textTheme.bodySmall,
        ),
      ),
    );
  }
}

String _hourLabel(int hour) {
  if (hour == 0) return '12a';
  if (hour == 12) return '12p';
  return hour < 12 ? '${hour}a' : '${hour - 12}p';
}

String _shortCurrency(double value) {
  if (value >= 1000000) return '${(value / 1000000).toStringAsFixed(1)}M';
  if (value >= 1000) return '${(value / 1000).toStringAsFixed(0)}k';
  return value.toStringAsFixed(0);
}
