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

/// "Menú": menu-engineering view. Surfaces the active dishes that did NOT sell
/// in the period (dead items) and classifies the ones that did into
/// star / plowhorse / puzzle / dog by popularity vs revenue.
class MenuEngineeringView extends ConsumerStatefulWidget {
  const MenuEngineeringView({
    super.key,
    required this.start,
    required this.end,
    this.periodLabel,
  });

  final DateTime start;
  final DateTime end;
  final String? periodLabel;

  @override
  ConsumerState<MenuEngineeringView> createState() => _MenuEngineeringViewState();
}

class _MenuEngineeringViewState extends ConsumerState<MenuEngineeringView> {
  late Future<MenuEngineeringReport> _future;
  late DateTime _start;
  late DateTime _end;
  late String _periodLabel;
  DetailPeriod _period = DetailPeriod.initial;
  DateTimeRange? _customRange;

  MenuEngineeringReport _loaded = const MenuEngineeringReport();

  @override
  void initState() {
    super.initState();
    _start = widget.start;
    _end = widget.end;
    _periodLabel = widget.periodLabel ?? 'Periodo';
    _future = _load();
  }

  Future<MenuEngineeringReport> _load() async {
    final profile = ref.read(authGateViewModelProvider).profile;
    final businessId = profile?.businessId;
    if (businessId == null) return const MenuEngineeringReport();
    final report = await ref.read(dashboardDataServiceProvider).loadMenuEngineering(
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
    rows.add(['SIN VENTA (${_loaded.deadItems.length})', '', '']);
    for (final name in _loaded.deadItems) {
      rows.add([name, '0', '0.00']);
    }
    rows.add(['', '', '']);
    rows.add(['PRODUCTOS VENDIDOS', '', '']);
    for (final p in _loaded.selling) {
      rows.add([
        p.name,
        MangoFormatters.number(p.units),
        MangoFormatters.amount(p.revenue),
      ]);
    }
    rows.add(['TOTAL INGRESOS', '', MangoFormatters.amount(_loaded.totalRevenue)]);
    return rows;
  }

  Future<void> _exportCsv() => ReportExportService.exportCsv(
        filename: 'menu_${_periodLabel.replaceAll(' ', '_')}',
        headers: const ['Producto', 'Unidades', 'Ingresos'],
        rows: _rowsForExport(),
        subject: 'Menú · $_periodLabel',
      );

  Future<void> _exportPdf() => ReportExportService.exportPdf(
        filename: 'menu_${_periodLabel.replaceAll(' ', '_')}',
        title: 'Análisis de menú',
        subtitle: 'Periodo: $_periodLabel',
        headers: const ['Producto', 'Unidades', 'Ingresos'],
        rows: _rowsForExport(),
      );

  @override
  Widget build(BuildContext context) {
    final dpi = DpiScale.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Menú'),
        centerTitle: false,
        actions: [
          ExportMenuButton(
            enabled: _loaded.selling.isNotEmpty || _loaded.deadItems.isNotEmpty,
            onExportCsv: _exportCsv,
            onExportPdf: _exportPdf,
          ),
        ],
      ),
      body: FutureBuilder<MenuEngineeringReport>(
        future: _future,
        builder: (context, snapshot) {
          final loading = snapshot.connectionState == ConnectionState.waiting;
          final report = snapshot.data ?? const MenuEngineeringReport();
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
                    return _centered(context, 'No se pudo cargar el análisis de menú.', danger: true);
                  }
                  if (report.menuSize == 0 && report.selling.isEmpty) {
                    return _centered(context, 'No hay datos de menú en este periodo.');
                  }
                  return ListView(
                    physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
                    padding: EdgeInsets.fromLTRB(dpi.space(16), 0, dpi.space(16),
                        dpi.space(16) + MediaQuery.of(context).padding.bottom),
                    children: [
                      _DeadItemsCard(items: report.deadItems),
                      SizedBox(height: dpi.space(12)),
                      _SoldProductsCard(selling: report.selling),
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

class _Header extends StatelessWidget {
  const _Header({required this.report, required this.periodLabel});
  final MenuEngineeringReport report;
  final String periodLabel;

  @override
  Widget build(BuildContext context) {
    final dpi = DpiScale.of(context);
    final dead = report.deadItems.length;
    return Container(
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
              Icon(Icons.restaurant_menu_rounded, color: Colors.white, size: dpi.icon(18)),
              SizedBox(width: dpi.space(6)),
              Text('Análisis de menú · $periodLabel',
                  style: TextStyle(
                      color: Colors.white, fontSize: dpi.font(12), fontWeight: FontWeight.w600)),
            ],
          ),
          SizedBox(height: dpi.space(10)),
          Text('Platos sin venta',
              style: TextStyle(color: Colors.white70, fontSize: dpi.font(11))),
          SizedBox(height: dpi.space(2)),
          Text('$dead',
              style: TextStyle(color: Colors.white, fontSize: dpi.font(26), fontWeight: FontWeight.w800)),
          SizedBox(height: dpi.space(10)),
          Row(
            children: [
              Expanded(child: _MiniStat(label: 'En menú', value: MangoFormatters.number(report.menuSize))),
              Container(width: 1, height: dpi.scale(26), color: Colors.white.withValues(alpha: 0.22)),
              Expanded(child: _MiniStat(label: 'Con venta', value: MangoFormatters.number(report.selling.length))),
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

class _DeadItemsCard extends StatelessWidget {
  const _DeadItemsCard({required this.items});
  final List<String> items;

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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.block_rounded, color: MangoThemeFactory.danger, size: dpi.icon(18)),
              SizedBox(width: dpi.space(8)),
              Text('Sin venta en el periodo',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
            ],
          ),
          SizedBox(height: dpi.space(4)),
          Text('Platos activos en el menú que no se vendieron',
              style: TextStyle(fontSize: dpi.font(11), color: MangoThemeFactory.mutedText(context))),
          SizedBox(height: dpi.space(12)),
          if (items.isEmpty)
            Row(children: [
              Icon(Icons.check_circle_rounded, color: MangoThemeFactory.success, size: dpi.icon(18)),
              SizedBox(width: dpi.space(8)),
              Expanded(
                child: Text('¡Todos los platos activos se vendieron!',
                    style: Theme.of(context).textTheme.bodyMedium),
              ),
            ])
          else
            Wrap(
              spacing: dpi.space(8),
              runSpacing: dpi.space(8),
              children: [
                for (final name in items)
                  Container(
                    padding: EdgeInsets.symmetric(
                        horizontal: dpi.space(10), vertical: dpi.space(6)),
                    decoration: BoxDecoration(
                      color: MangoThemeFactory.danger.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(dpi.radius(10)),
                      border: Border.all(color: MangoThemeFactory.danger.withValues(alpha: 0.3)),
                    ),
                    child: Text(name,
                        style: TextStyle(
                            fontSize: dpi.font(12),
                            fontWeight: FontWeight.w600,
                            color: MangoThemeFactory.textColor(context))),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

class _SoldProductsCard extends StatelessWidget {
  const _SoldProductsCard({required this.selling});
  final List<MenuItemStat> selling;

  @override
  Widget build(BuildContext context) {
    final dpi = DpiScale.of(context);
    final maxRevenue = selling.fold<double>(0, (m, p) => p.revenue > m ? p.revenue : m);
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
              Icon(Icons.insights_rounded, color: MangoThemeFactory.mango, size: dpi.icon(18)),
              SizedBox(width: dpi.space(8)),
              Text('Productos vendidos',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
            ],
          ),
          SizedBox(height: dpi.space(4)),
          Text('Ordenados por ingresos del periodo',
              style: TextStyle(fontSize: dpi.font(11), color: MangoThemeFactory.mutedText(context))),
          SizedBox(height: dpi.space(12)),
          if (selling.isEmpty)
            Text('Sin ventas de productos en este periodo.',
                style: Theme.of(context).textTheme.bodySmall)
          else
            for (final p in selling) ...[
              _SoldRow(stat: p, share: maxRevenue == 0 ? 0 : p.revenue / maxRevenue),
              SizedBox(height: dpi.space(10)),
            ],
        ],
      ),
    );
  }
}

class _SoldRow extends StatelessWidget {
  const _SoldRow({required this.stat, required this.share});
  final MenuItemStat stat;
  final double share;

  @override
  Widget build(BuildContext context) {
    final dpi = DpiScale.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(stat.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
            ),
            SizedBox(width: dpi.space(8)),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(MangoFormatters.currency(stat.revenue),
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
                    colors: [MangoThemeFactory.mango, MangoThemeFactory.mango.withValues(alpha: 0.7)],
                  ),
                  borderRadius: BorderRadius.circular(dpi.radius(3)),
                ),
              ),
            ),
          ],
        ),
        SizedBox(height: dpi.space(3)),
        Text('${MangoFormatters.number(stat.units)} ${stat.units == 1 ? 'unidad' : 'unidades'}',
            style: TextStyle(fontSize: dpi.font(10), color: MangoThemeFactory.mutedText(context))),
      ],
    );
  }
}
