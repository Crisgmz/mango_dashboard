import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/di/providers.dart';
import '../../../core/date/date_range_utils.dart';
import '../../../core/formatters/mango_formatters.dart';
import '../../../core/responsive/dpi_scale.dart';
import '../../../data/export/report_export_service.dart';
import '../../../domain/dashboard/dashboard_models.dart';
import '../../auth/viewmodel/auth_gate_view_model.dart';
import '../../theme/theme_data_factory.dart';
import '../widgets/period_filter_bar.dart';

/// "Operación": where and how the period's sales happen — by zone, by origin
/// (dine-in / delivery / …) and by table — plus service metrics (table
/// turnover, covers, ticket per person). Helps the owner read the floor.
class OperationsView extends ConsumerStatefulWidget {
  const OperationsView({
    super.key,
    required this.start,
    required this.end,
    this.periodLabel,
  });

  final DateTime start;
  final DateTime end;
  final String? periodLabel;

  @override
  ConsumerState<OperationsView> createState() => _OperationsViewState();
}

class _OperationsViewState extends ConsumerState<OperationsView> {
  late Future<OperationsReport> _future;
  late DateTime _start;
  late DateTime _end;
  late String _periodLabel;
  DetailPeriod _period = DetailPeriod.initial;
  DateTimeRange? _customRange;

  OperationsReport _loaded = const OperationsReport();

  @override
  void initState() {
    super.initState();
    _start = widget.start;
    _end = widget.end;
    _periodLabel = widget.periodLabel ?? 'Periodo';
    _future = _load();
  }

  Future<OperationsReport> _load() async {
    final profile = ref.read(authGateViewModelProvider).profile;
    final businessId = profile?.businessId;
    if (businessId == null) return const OperationsReport();
    final report = await ref.read(dashboardDataServiceProvider).loadOperations(
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
    final firstDate = DateTime(now.year - 3);
    final lastDate = DateTime(now.year, now.month, now.day);
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
      _future = _load();
    });
  }

  List<List<String>> _rowsForExport() {
    final rows = <List<String>>[];
    rows.add(['VENTAS POR ZONA', '', '']);
    for (final z in _loaded.zones) {
      rows.add([z.name, MangoFormatters.number(z.orderCount), MangoFormatters.amount(z.total)]);
    }
    rows.add(['', '', '']);
    rows.add(['POR ORIGEN', '', '']);
    for (final o in _loaded.origins) {
      rows.add([_originLabel(o.name), MangoFormatters.number(o.orderCount), MangoFormatters.amount(o.total)]);
    }
    rows.add(['', '', '']);
    rows.add(['Rotación promedio de mesa', '', _turnover(_loaded.avgTurnoverMinutes)]);
    rows.add(['Ticket por persona', '', MangoFormatters.amount(_loaded.ticketPerPerson)]);
    rows.add(['Comensales', '', MangoFormatters.number(_loaded.totalCovers)]);
    rows.add(['Sesiones', '', MangoFormatters.number(_loaded.sessionCount)]);
    rows.add(['TOTAL', '', MangoFormatters.amount(_loaded.totalSales)]);
    return rows;
  }

  Future<void> _exportCsv() => ReportExportService.exportCsv(
        filename: 'operacion_${_periodLabel.replaceAll(' ', '_')}',
        headers: const ['Concepto', 'Órdenes', 'Monto'],
        rows: _rowsForExport(),
        subject: 'Operación · $_periodLabel',
      );

  Future<void> _exportPdf() => ReportExportService.exportPdf(
        filename: 'operacion_${_periodLabel.replaceAll(' ', '_')}',
        title: 'Operación (mesas y zonas)',
        subtitle: 'Periodo: $_periodLabel',
        headers: const ['Concepto', 'Órdenes', 'Monto'],
        rows: _rowsForExport(),
      );

  @override
  Widget build(BuildContext context) {
    final dpi = DpiScale.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Operación'),
        centerTitle: false,
        actions: [
          ExportMenuButton(
            enabled: _loaded.totalSales > 0,
            onExportCsv: _exportCsv,
            onExportPdf: _exportPdf,
          ),
        ],
      ),
      body: FutureBuilder<OperationsReport>(
        future: _future,
        builder: (context, snapshot) {
          final loading = snapshot.connectionState == ConnectionState.waiting;
          final report = snapshot.data ?? const OperationsReport();
          return Column(
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(dpi.space(16), dpi.space(16), dpi.space(16), 0),
                child: _Header(report: report, periodLabel: _periodLabel),
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
                  if (snapshot.hasError) {
                    return _centered(context, 'No se pudo cargar la operación.', danger: true);
                  }
                  if (report.totalSales <= 0) {
                    return _centered(context, 'No hubo ventas en este periodo.');
                  }
                  return ListView(
                    physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
                    padding: EdgeInsets.fromLTRB(dpi.space(16), 0, dpi.space(16),
                        dpi.space(16) + MediaQuery.of(context).padding.bottom),
                    children: [
                      _KpiStrip(report: report),
                      SizedBox(height: dpi.space(12)),
                      _BreakdownCard(
                        icon: Icons.map_rounded,
                        accent: MangoThemeFactory.info,
                        title: 'Ventas por zona',
                        items: report.zones,
                      ),
                      SizedBox(height: dpi.space(12)),
                      _BreakdownCard(
                        icon: Icons.delivery_dining_rounded,
                        accent: MangoThemeFactory.mango,
                        title: 'Por origen',
                        items: report.origins,
                        labelFor: _originLabel,
                      ),
                      if (report.tables.isNotEmpty) ...[
                        SizedBox(height: dpi.space(12)),
                        _BreakdownCard(
                          icon: Icons.table_restaurant_rounded,
                          accent: MangoThemeFactory.success,
                          title: 'Mesas que más venden',
                          items: report.tables.take(8).toList(),
                        ),
                      ],
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

  Widget _centered(BuildContext context, String text, {bool danger = false}) {
    final dpi = DpiScale.of(context);
    return Center(
      child: Padding(
        padding: EdgeInsets.all(dpi.space(20)),
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

String _originLabel(String o) {
  switch (o) {
    case 'dine_in':
      return 'En mesa';
    case 'delivery':
      return 'Delivery';
    case 'quick':
      return 'Rápido';
    case 'manual':
      return 'Manual';
    case 'self_service':
      return 'Autoservicio';
    default:
      return o;
  }
}

String _turnover(double minutes) {
  if (minutes <= 0) return '—';
  final m = minutes.round();
  if (m >= 60) {
    final h = m ~/ 60;
    final r = m % 60;
    return r == 0 ? '${h}h' : '${h}h ${r}m';
  }
  return '$m min';
}

class _Header extends StatelessWidget {
  const _Header({required this.report, required this.periodLabel});
  final OperationsReport report;
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
              Icon(Icons.storefront_rounded, color: Colors.white, size: dpi.icon(18)),
              SizedBox(width: dpi.space(6)),
              Text(
                'Operación · $periodLabel',
                style: TextStyle(
                    color: Colors.white, fontSize: dpi.font(12), fontWeight: FontWeight.w600),
              ),
            ],
          ),
          SizedBox(height: dpi.space(10)),
          Text('Ventas del periodo',
              style: TextStyle(color: Colors.white70, fontSize: dpi.font(11))),
          SizedBox(height: dpi.space(2)),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              MangoFormatters.currency(report.totalSales),
              style: TextStyle(
                  color: Colors.white, fontSize: dpi.font(24), fontWeight: FontWeight.w800),
            ),
          ),
          SizedBox(height: dpi.space(10)),
          Row(
            children: [
              Expanded(child: _MiniStat(label: 'Sesiones', value: MangoFormatters.number(report.sessionCount))),
              Container(width: 1, height: dpi.scale(26), color: Colors.white.withValues(alpha: 0.22)),
              Expanded(child: _MiniStat(label: 'Órdenes', value: MangoFormatters.number(report.orderCount))),
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
    return Column(
      children: [
        Text(label, style: TextStyle(color: Colors.white70, fontSize: dpi.font(10))),
        SizedBox(height: dpi.space(2)),
        Text(value,
            style: TextStyle(color: Colors.white, fontSize: dpi.font(15), fontWeight: FontWeight.w800)),
      ],
    );
  }
}

class _KpiStrip extends StatelessWidget {
  const _KpiStrip({required this.report});
  final OperationsReport report;

  @override
  Widget build(BuildContext context) {
    final dpi = DpiScale.of(context);
    Widget kpi(IconData icon, String label, String value) => Expanded(
          child: Container(
            padding: EdgeInsets.all(dpi.space(12)),
            decoration: BoxDecoration(
              color: MangoThemeFactory.cardColor(context),
              borderRadius: BorderRadius.circular(dpi.radius(14)),
              border: Border.all(color: MangoThemeFactory.borderColor(context)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, size: dpi.icon(18), color: MangoThemeFactory.info),
                SizedBox(height: dpi.space(8)),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(value,
                      style: TextStyle(
                          fontSize: dpi.font(16),
                          fontWeight: FontWeight.w800,
                          color: MangoThemeFactory.textColor(context))),
                ),
                SizedBox(height: dpi.space(2)),
                Text(label,
                    style: TextStyle(
                        fontSize: dpi.font(10), color: MangoThemeFactory.mutedText(context))),
              ],
            ),
          ),
        );

    return Row(
      children: [
        kpi(Icons.timer_outlined, 'Rotación mesa', _turnover(report.avgTurnoverMinutes)),
        SizedBox(width: dpi.space(10)),
        kpi(Icons.person_outline_rounded, 'Ticket/persona',
            MangoFormatters.currency(report.ticketPerPerson)),
        SizedBox(width: dpi.space(10)),
        kpi(Icons.groups_outlined, 'Comensales', MangoFormatters.number(report.totalCovers)),
      ],
    );
  }
}

class _BreakdownCard extends StatelessWidget {
  const _BreakdownCard({
    required this.icon,
    required this.accent,
    required this.title,
    required this.items,
    this.labelFor,
  });

  final IconData icon;
  final Color accent;
  final String title;
  final List<NamedSales> items;
  final String Function(String)? labelFor;

  @override
  Widget build(BuildContext context) {
    final dpi = DpiScale.of(context);
    final maxValue = items.fold<double>(0, (m, i) => i.total > m ? i.total : m);
    final grand = items.fold<double>(0, (s, i) => s + i.total);

    return Container(
      padding: EdgeInsets.all(dpi.space(16)),
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
              Icon(icon, color: accent, size: dpi.icon(18)),
              SizedBox(width: dpi.space(8)),
              Text(title,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
            ],
          ),
          SizedBox(height: dpi.space(12)),
          for (final item in items) ...[
            _Row(
              label: labelFor?.call(item.name) ?? item.name,
              value: item.total,
              orderCount: item.orderCount,
              share: maxValue == 0 ? 0 : item.total / maxValue,
              pct: grand == 0 ? 0 : item.total / grand,
              accent: accent,
            ),
            SizedBox(height: dpi.space(10)),
          ],
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.label,
    required this.value,
    required this.orderCount,
    required this.share,
    required this.pct,
    required this.accent,
  });

  final String label;
  final double value;
  final int orderCount;
  final double share;
  final double pct;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final dpi = DpiScale.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
            ),
            SizedBox(width: dpi.space(8)),
            Text('${(pct * 100).toStringAsFixed(0)}%',
                style: TextStyle(
                    fontSize: dpi.font(11),
                    color: MangoThemeFactory.mutedText(context),
                    fontWeight: FontWeight.w600)),
            SizedBox(width: dpi.space(10)),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(MangoFormatters.currency(value),
                  style: TextStyle(
                      fontSize: dpi.font(13),
                      fontWeight: FontWeight.w800,
                      color: MangoThemeFactory.textColor(context))),
            ),
          ],
        ),
        SizedBox(height: dpi.space(6)),
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
                    colors: [accent, accent.withValues(alpha: 0.7)],
                  ),
                  borderRadius: BorderRadius.circular(dpi.radius(3)),
                ),
              ),
            ),
          ],
        ),
        SizedBox(height: dpi.space(3)),
        Text('${MangoFormatters.number(orderCount)} ${orderCount == 1 ? 'orden' : 'órdenes'}',
            style: TextStyle(fontSize: dpi.font(10), color: MangoThemeFactory.mutedText(context))),
      ],
    );
  }
}
