import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/di/providers.dart';
import '../../../core/formatters/mango_formatters.dart';
import '../../../core/date/date_range_utils.dart';
import '../../../core/responsive/dpi_scale.dart';
import '../../../domain/dashboard/dashboard_models.dart';
import '../../../data/export/report_export_service.dart';
import '../../auth/viewmodel/auth_gate_view_model.dart';
import '../../theme/theme_data_factory.dart';
import '../widgets/period_filter_bar.dart';

/// Ranking of modifiers (extras / opciones) sold in the period: how many
/// times each one was added and how much revenue it generated.
class ModifiersBreakdownView extends ConsumerStatefulWidget {
  const ModifiersBreakdownView({
    super.key,
    required this.start,
    required this.end,
    this.periodLabel,
  });

  final DateTime start;
  final DateTime end;
  final String? periodLabel;

  @override
  ConsumerState<ModifiersBreakdownView> createState() => _ModifiersBreakdownViewState();
}

class _ModifiersBreakdownViewState extends ConsumerState<ModifiersBreakdownView> {
  late Future<List<ModifierSummary>> _future;
  late DateTime _start;
  late DateTime _end;
  late String _periodLabel;
  DetailPeriod _period = DetailPeriod.initial;
  DateTimeRange? _customRange;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _start = widget.start;
    _end = widget.end;
    _periodLabel = widget.periodLabel ?? 'Periodo';
    _future = _load();
  }

  List<ModifierSummary> _loaded = const [];

  Future<List<ModifierSummary>> _load() async {
    final profile = ref.read(authGateViewModelProvider).profile;
    final businessId = profile?.businessId;
    if (businessId == null) return const [];
    final rows = await ref.read(dashboardDataServiceProvider).loadModifiersBreakdown(
          businessId: businessId,
          start: _start,
          end: _end,
        );
    if (mounted) setState(() => _loaded = rows);
    return rows;
  }

  List<List<String>> _rowsForExport() {
    final q = _query.trim().toLowerCase();
    final filtered = q.isEmpty
        ? _loaded
        : _loaded.where((m) => m.name.toLowerCase().contains(q)).toList();
    return filtered
        .map((m) => [
              m.name,
              m.count.round().toString(),
              m.revenue.toStringAsFixed(2),
            ])
        .toList();
  }

  Future<void> _exportCsv() async {
    await ReportExportService.exportCsv(
      filename: 'modificadores_${_periodLabel.replaceAll(' ', '_')}',
      headers: const ['Modificador', 'Usos', 'Ingreso'],
      rows: _rowsForExport(),
      subject: 'Reporte de modificadores · $_periodLabel',
    );
  }

  Future<void> _exportPdf() async {
    await ReportExportService.exportPdf(
      filename: 'modificadores_${_periodLabel.replaceAll(' ', '_')}',
      title: 'Modificadores',
      subtitle: 'Periodo: $_periodLabel',
      headers: const ['Modificador', 'Usos', 'Ingreso'],
      rows: _rowsForExport(),
    );
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
    final end = DateTime(picked.end.year, picked.end.month, picked.end.day).add(const Duration(days: 1));
    setState(() {
      _period = DetailPeriod.custom;
      _customRange = picked;
      _start = start;
      _end = end;
      _periodLabel = labelForDetailPeriod(DetailPeriod.custom, customRange: picked);
      _future = _load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final dpi = DpiScale.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Modificadores'),
        centerTitle: false,
        actions: [
          ExportMenuButton(
            enabled: _loaded.isNotEmpty,
            onExportCsv: _exportCsv,
            onExportPdf: _exportPdf,
          ),
        ],
      ),
      body: FutureBuilder<List<ModifierSummary>>(
        future: _future,
        builder: (context, snapshot) {
          final loading = snapshot.connectionState == ConnectionState.waiting;
          final hasError = snapshot.hasError;
          final all = snapshot.data ?? const <ModifierSummary>[];
          final q = _query.trim().toLowerCase();
          final modifiers = q.isEmpty
              ? all
              : all.where((m) => m.name.toLowerCase().contains(q)).toList();
          final totalUses = modifiers.fold<double>(0, (s, m) => s + m.count);
          final totalRevenue = modifiers.fold<double>(0, (s, m) => s + m.revenue);
          final maxRevenue = modifiers.isEmpty
              ? 0.0
              : modifiers.first.revenue == 0
                  ? modifiers.first.count
                  : modifiers.first.revenue;

          return Column(
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(dpi.space(16), dpi.space(16), dpi.space(16), 0),
                child: _Header(
                  totalUses: totalUses,
                  totalRevenue: totalRevenue,
                  uniqueModifiers: modifiers.length,
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
              Padding(
                padding: EdgeInsets.symmetric(horizontal: dpi.space(16)),
                child: TextField(
                  onChanged: (v) => setState(() => _query = v),
                  decoration: InputDecoration(
                    hintText: 'Buscar modificador…',
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
                  if (modifiers.isEmpty) {
                    return Center(
                      child: Padding(
                        padding: EdgeInsets.all(dpi.space(20)),
                        child: Text(
                          q.isEmpty
                              ? 'No se aplicaron modificadores en este periodo.'
                              : 'Sin resultados para "$_query".',
                          style: Theme.of(context).textTheme.bodySmall,
                          textAlign: TextAlign.center,
                        ),
                      ),
                    );
                  }
                  return ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
                    padding: EdgeInsets.fromLTRB(dpi.space(16), 0, dpi.space(16),
                        dpi.space(16) + MediaQuery.of(context).padding.bottom),
                    itemCount: modifiers.length,
                    separatorBuilder: (_, _) => SizedBox(height: dpi.space(10)),
                    itemBuilder: (context, i) => _ModifierRow(
                      rank: i + 1,
                      data: modifiers[i],
                      maxValue: maxRevenue,
                    ),
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

class _Header extends StatelessWidget {
  const _Header({
    required this.totalUses,
    required this.totalRevenue,
    required this.uniqueModifiers,
    required this.periodLabel,
  });
  final double totalUses;
  final double totalRevenue;
  final int uniqueModifiers;
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
              Icon(Icons.tune_rounded, color: Colors.white, size: dpi.icon(18)),
              SizedBox(width: dpi.space(6)),
              Text(
                'Modificadores · $periodLabel',
                style: TextStyle(color: Colors.white, fontSize: dpi.font(12), fontWeight: FontWeight.w600),
              ),
            ],
          ),
          SizedBox(height: dpi.space(10)),
          Text(
            'Ingresos por modificadores',
            style: TextStyle(color: Colors.white70, fontSize: dpi.font(11)),
          ),
          SizedBox(height: dpi.space(2)),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              MangoFormatters.currency(totalRevenue),
              style: TextStyle(color: Colors.white, fontSize: dpi.font(24), fontWeight: FontWeight.w800),
            ),
          ),
          SizedBox(height: dpi.space(10)),
          Row(
            children: [
              Expanded(
                child: _MiniStat(
                  label: 'Distintos',
                  value: '$uniqueModifiers',
                ),
              ),
              Container(width: 1, height: dpi.scale(26), color: Colors.white.withValues(alpha: 0.22)),
              Expanded(
                child: _MiniStat(
                  label: 'Usos totales',
                  value: MangoFormatters.number(totalUses.round()),
                ),
              ),
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
          Text(
            value,
            style: TextStyle(color: Colors.white, fontSize: dpi.font(15), fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

class _ModifierRow extends StatelessWidget {
  const _ModifierRow({required this.rank, required this.data, required this.maxValue});
  final int rank;
  final ModifierSummary data;
  final double maxValue;

  @override
  Widget build(BuildContext context) {
    final dpi = DpiScale.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // Use revenue when available, fallback to count for free modifiers.
    final value = data.revenue != 0 ? data.revenue : data.count;
    final share = maxValue == 0 ? 0.0 : (value / maxValue);

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
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: dpi.scale(28),
                height: dpi.scale(28),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: rankColor.withValues(alpha: isDark ? 0.2 : 0.12),
                  borderRadius: BorderRadius.circular(dpi.radius(8)),
                ),
                child: Text(
                  '$rank',
                  style: TextStyle(
                    fontSize: dpi.font(11),
                    fontWeight: FontWeight.w800,
                    color: rankColor,
                  ),
                ),
              ),
              SizedBox(width: dpi.space(10)),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      data.name,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    SizedBox(height: dpi.space(2)),
                    Text(
                      '${MangoFormatters.number(data.count.round())} ${data.count == 1 ? 'uso' : 'usos'}',
                      style: TextStyle(fontSize: dpi.font(11), color: MangoThemeFactory.mutedText(context)),
                    ),
                  ],
                ),
              ),
              SizedBox(width: dpi.space(8)),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      MangoFormatters.currency(data.revenue),
                      style: TextStyle(
                        fontSize: dpi.font(13),
                        fontWeight: FontWeight.w800,
                        color: MangoThemeFactory.info,
                      ),
                    ),
                  ),
                  if (data.revenue == 0)
                    Text(
                      'gratuito',
                      style: TextStyle(
                        fontSize: dpi.font(9),
                        color: MangoThemeFactory.mutedText(context),
                      ),
                    ),
                ],
              ),
            ],
          ),
          SizedBox(height: dpi.space(8)),
          Padding(
            padding: EdgeInsets.only(left: dpi.space(38)),
            child: Stack(
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
          ),
        ],
      ),
    );
  }
}
