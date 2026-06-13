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

/// "Fiscal": NCF issued by type, e-CF DGII status (accepted / pending /
/// rejected) and consolidated ITBIS for the period — the compliance view for
/// the Dominican Republic (606/607 + e-CF monitoring).
class FiscalView extends ConsumerStatefulWidget {
  const FiscalView({
    super.key,
    required this.start,
    required this.end,
    this.periodLabel,
  });

  final DateTime start;
  final DateTime end;
  final String? periodLabel;

  @override
  ConsumerState<FiscalView> createState() => _FiscalViewState();
}

class _FiscalViewState extends ConsumerState<FiscalView> {
  late Future<FiscalReport> _future;
  late DateTime _start;
  late DateTime _end;
  late String _periodLabel;
  DetailPeriod _period = DetailPeriod.initial;
  DateTimeRange? _customRange;

  FiscalReport _loaded = const FiscalReport();

  @override
  void initState() {
    super.initState();
    _start = widget.start;
    _end = widget.end;
    _periodLabel = widget.periodLabel ?? 'Periodo';
    _future = _load();
  }

  Future<FiscalReport> _load() async {
    final profile = ref.read(authGateViewModelProvider).profile;
    final businessId = profile?.businessId;
    if (businessId == null) return const FiscalReport();
    final report = await ref.read(dashboardDataServiceProvider).loadFiscal(
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
    rows.add(['NCF POR TIPO', '', '']);
    for (final t in _loaded.byType) {
      rows.add([_ncfTypeLabel(t.type), MangoFormatters.number(t.count), MangoFormatters.amount(t.total)]);
    }
    rows.add(['', '', '']);
    rows.add(['TOTAL FACTURADO', MangoFormatters.number(_loaded.documentCount), MangoFormatters.amount(_loaded.total)]);
    if (_loaded.taxes.isNotEmpty) {
      rows.add(['', '', '']);
      rows.add(['IMPUESTOS RECAUDADOS', '', '']);
      for (final t in _loaded.taxes) {
        rows.add([_taxLabel(t), '', MangoFormatters.amount(t.amount)]);
      }
      rows.add(['Total impuestos', '', MangoFormatters.amount(_loaded.taxTotal)]);
    }
    if (_loaded.cancelledCount > 0) {
      rows.add(['Anulados', MangoFormatters.number(_loaded.cancelledCount), '']);
    }
    return rows;
  }

  Future<void> _exportCsv() => ReportExportService.exportCsv(
        filename: 'fiscal_${_periodLabel.replaceAll(' ', '_')}',
        headers: const ['Concepto', 'Cantidad', 'Monto'],
        rows: _rowsForExport(),
        subject: 'Fiscal · $_periodLabel',
      );

  Future<void> _exportPdf() => ReportExportService.exportPdf(
        filename: 'fiscal_${_periodLabel.replaceAll(' ', '_')}',
        title: 'Reporte fiscal (NCF / e-CF)',
        subtitle: 'Periodo: $_periodLabel',
        headers: const ['Concepto', 'Cantidad', 'Monto'],
        rows: _rowsForExport(),
      );

  @override
  Widget build(BuildContext context) {
    final dpi = DpiScale.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Fiscal'),
        centerTitle: false,
        actions: [
          ExportMenuButton(
            enabled: _loaded.documentCount > 0,
            onExportCsv: _exportCsv,
            onExportPdf: _exportPdf,
          ),
        ],
      ),
      body: FutureBuilder<FiscalReport>(
        future: _future,
        builder: (context, snapshot) {
          final loading = snapshot.connectionState == ConnectionState.waiting;
          final report = snapshot.data ?? const FiscalReport();
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
                    return _centered(context, 'No se pudo cargar el reporte fiscal.', danger: true);
                  }
                  if (report.documentCount == 0 && report.cancelledCount == 0) {
                    return _centered(context, 'No se emitieron comprobantes en este periodo.');
                  }
                  return ListView(
                    physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
                    padding: EdgeInsets.fromLTRB(dpi.space(16), 0, dpi.space(16),
                        dpi.space(16) + MediaQuery.of(context).padding.bottom),
                    children: [
                      if (report.taxes.isNotEmpty) ...[
                        _TaxesCard(taxes: report.taxes),
                        SizedBox(height: dpi.space(12)),
                      ],
                      _NcfTypesCard(report: report),
                      if (report.cancelledCount > 0) ...[
                        SizedBox(height: dpi.space(12)),
                        _CancelledNote(count: report.cancelledCount),
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

String _ncfTypeLabel(String t) {
  switch (t.toUpperCase()) {
    case 'B01':
      return 'B01 · Crédito fiscal';
    case 'B02':
      return 'B02 · Consumo';
    case 'B03':
      return 'B03 · Nota de débito';
    case 'B04':
      return 'B04 · Nota de crédito';
    case 'B11':
      return 'B11 · Comprobante de compras';
    case 'B13':
      return 'B13 · Gastos menores';
    case 'B14':
      return 'B14 · Régimen especial';
    case 'B15':
      return 'B15 · Gubernamental';
    case 'B16':
      return 'B16 · Exportaciones';
    case 'E31':
      return 'E31 · e-CF Crédito fiscal';
    case 'E32':
      return 'E32 · e-CF Consumo';
    case 'E33':
      return 'E33 · e-CF Nota de débito';
    case 'E34':
      return 'E34 · e-CF Nota de crédito';
    case 'E41':
      return 'E41 · e-CF Compras';
    case 'E43':
      return 'E43 · e-CF Gastos menores';
    case 'E44':
      return 'E44 · e-CF Régimen especial';
    case 'E45':
      return 'E45 · e-CF Gubernamental';
    default:
      return t;
  }
}

/// Tax name + its rate when known (e.g. "ITBIS (18%)"); just the name otherwise.
String _taxLabel(TaxLineTotal t) {
  final r = t.rate;
  if (r == null || r <= 0) return t.name;
  final pct = r < 1 ? r * 100 : r; // accept 0.18 or 18
  final pctStr = pct == pct.roundToDouble() ? pct.toStringAsFixed(0) : pct.toStringAsFixed(2);
  return '${t.name} ($pctStr%)';
}

class _Header extends StatelessWidget {
  const _Header({required this.report, required this.periodLabel});
  final FiscalReport report;
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
              Icon(Icons.receipt_long_rounded, color: Colors.white, size: dpi.icon(18)),
              SizedBox(width: dpi.space(6)),
              Text('Fiscal · $periodLabel',
                  style: TextStyle(
                      color: Colors.white, fontSize: dpi.font(12), fontWeight: FontWeight.w600)),
            ],
          ),
          SizedBox(height: dpi.space(10)),
          Text('Impuestos recaudados',
              style: TextStyle(color: Colors.white70, fontSize: dpi.font(11))),
          SizedBox(height: dpi.space(2)),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              MangoFormatters.currency(report.taxTotal),
              style: TextStyle(
                  color: Colors.white, fontSize: dpi.font(24), fontWeight: FontWeight.w800),
            ),
          ),
          SizedBox(height: dpi.space(10)),
          Row(
            children: [
              Expanded(child: _MiniStat(label: 'Facturado', value: MangoFormatters.currency(report.total))),
              Container(width: 1, height: dpi.scale(26), color: Colors.white.withValues(alpha: 0.22)),
              Expanded(child: _MiniStat(label: 'Comprobantes', value: MangoFormatters.number(report.documentCount))),
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
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(value,
              style: TextStyle(color: Colors.white, fontSize: dpi.font(15), fontWeight: FontWeight.w800)),
        ),
      ],
    );
  }
}

class _TaxesCard extends StatelessWidget {
  const _TaxesCard({required this.taxes});
  final List<TaxLineTotal> taxes;

  @override
  Widget build(BuildContext context) {
    final dpi = DpiScale.of(context);
    final total = taxes.fold<double>(0, (s, t) => s + t.amount);
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
              Icon(Icons.percent_rounded, color: MangoThemeFactory.info, size: dpi.icon(18)),
              SizedBox(width: dpi.space(8)),
              Text('Impuestos del periodo',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
            ],
          ),
          SizedBox(height: dpi.space(4)),
          Text('Impuestos y cargos aplicados sobre las ventas',
              style: TextStyle(fontSize: dpi.font(11), color: MangoThemeFactory.mutedText(context))),
          SizedBox(height: dpi.space(10)),
          for (final t in taxes)
            Padding(
              padding: EdgeInsets.symmetric(vertical: dpi.space(6)),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Flexible(
                    child: Text(_taxLabel(t),
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: MangoThemeFactory.mutedText(context))),
                  ),
                  SizedBox(width: dpi.space(10)),
                  Text(MangoFormatters.currency(t.amount),
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: MangoThemeFactory.textColor(context))),
                ],
              ),
            ),
          const _ThinDivider(),
          Padding(
            padding: EdgeInsets.symmetric(vertical: dpi.space(6)),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Total impuestos',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w800)),
                Text(MangoFormatters.currency(total),
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800, color: MangoThemeFactory.info)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _NcfTypesCard extends StatelessWidget {
  const _NcfTypesCard({required this.report});
  final FiscalReport report;

  @override
  Widget build(BuildContext context) {
    final dpi = DpiScale.of(context);
    final maxTotal = report.byType.fold<double>(0, (m, t) => t.total > m ? t.total : m);
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
              Icon(Icons.fact_check_rounded, color: MangoThemeFactory.info, size: dpi.icon(18)),
              SizedBox(width: dpi.space(8)),
              Text('NCF por tipo',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
            ],
          ),
          SizedBox(height: dpi.space(12)),
          if (report.byType.isEmpty)
            Text('Sin comprobantes activos en este periodo.',
                style: Theme.of(context).textTheme.bodySmall)
          else
            for (final t in report.byType) ...[
              _TypeRow(stat: t, share: maxTotal == 0 ? 0 : t.total / maxTotal),
              SizedBox(height: dpi.space(10)),
            ],
          const _ThinDivider(),
          _summaryRow(context, 'Total facturado', report.total, bold: true),
        ],
      ),
    );
  }

  Widget _summaryRow(BuildContext context, String label, double value, {bool bold = false}) {
    final dpi = DpiScale.of(context);
    return Padding(
      padding: EdgeInsets.symmetric(vertical: dpi.space(5)),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: bold ? FontWeight.w800 : FontWeight.w500,
                  color: bold ? null : MangoThemeFactory.mutedText(context))),
          Text(MangoFormatters.currency(value),
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: bold ? FontWeight.w800 : FontWeight.w700,
                  color: bold ? MangoThemeFactory.info : MangoThemeFactory.textColor(context))),
        ],
      ),
    );
  }
}

class _TypeRow extends StatelessWidget {
  const _TypeRow({required this.stat, required this.share});
  final FiscalTypeSummary stat;
  final double share;

  @override
  Widget build(BuildContext context) {
    final dpi = DpiScale.of(context);
    final range = stat.firstNumber == null
        ? null
        : (stat.firstNumber == stat.lastNumber
            ? stat.firstNumber!
            : '${stat.firstNumber} → ${stat.lastNumber}');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(_ncfTypeLabel(stat.type),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
            ),
            SizedBox(width: dpi.space(8)),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(MangoFormatters.currency(stat.total),
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
                    colors: [MangoThemeFactory.info, MangoThemeFactory.info.withValues(alpha: 0.7)],
                  ),
                  borderRadius: BorderRadius.circular(dpi.radius(3)),
                ),
              ),
            ),
          ],
        ),
        SizedBox(height: dpi.space(3)),
        Text(
          '${MangoFormatters.number(stat.count)} comp.${range == null ? '' : ' · $range'}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: dpi.font(10), color: MangoThemeFactory.mutedText(context)),
        ),
      ],
    );
  }
}

class _CancelledNote extends StatelessWidget {
  const _CancelledNote({required this.count});
  final int count;

  @override
  Widget build(BuildContext context) {
    final dpi = DpiScale.of(context);
    return Container(
      padding: EdgeInsets.all(dpi.space(14)),
      decoration: BoxDecoration(
        color: MangoThemeFactory.cardColor(context),
        borderRadius: BorderRadius.circular(dpi.radius(14)),
        border: Border.all(color: MangoThemeFactory.borderColor(context)),
      ),
      child: Row(
        children: [
          Icon(Icons.cancel_outlined, color: MangoThemeFactory.warning, size: dpi.icon(18)),
          SizedBox(width: dpi.space(10)),
          Expanded(
            child: Text(
              '${MangoFormatters.number(count)} comprobante(s) anulado(s) en el periodo.',
              style: TextStyle(fontSize: dpi.font(12), color: MangoThemeFactory.mutedText(context)),
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
      padding: EdgeInsets.symmetric(vertical: dpi.space(6)),
      child: Divider(height: 1, color: MangoThemeFactory.borderColor(context)),
    );
  }
}
