import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/di/providers.dart';
import '../../../core/formatters/mango_formatters.dart';
import '../../../core/date/date_range_utils.dart';
import '../../../core/responsive/dpi_scale.dart';
import '../../../data/dashboard/business_day_service.dart';
import '../../../data/dashboard/report_result_cache.dart';
import '../../../data/export/report_export_service.dart';
import '../../../domain/dashboard/dashboard_models.dart';
import '../../auth/viewmodel/auth_gate_view_model.dart';
import '../../theme/theme_data_factory.dart';
import '../viewmodel/report_load_controller.dart';
import '../widgets/cash_movement_dialog.dart';
import '../widgets/period_filter_bar.dart';
import '../widgets/report_loading.dart';

/// Reporte de ingresos y egresos manuales de caja (depósitos, retiros y
/// gastos) del período, con la razón estructurada y la nota de cada
/// movimiento siempre visibles.
class IncomeExpenseReportView extends ConsumerStatefulWidget {
  const IncomeExpenseReportView({
    super.key,
    required this.start,
    required this.end,
    this.periodLabel,
  });

  final DateTime start;
  final DateTime end;
  final String? periodLabel;

  @override
  ConsumerState<IncomeExpenseReportView> createState() =>
      _IncomeExpenseReportViewState();
}

class _IncomeExpenseReportViewState
    extends ConsumerState<IncomeExpenseReportView>
    with SingleTickerProviderStateMixin {
  /// Controlador propio (en vez de DefaultTabController) para que el botón de
  /// nuevo movimiento abra en el tipo de la pestaña que se está viendo.
  late final TabController _tabs = TabController(length: 2, vsync: this);
  late final ReportLoadController<List<CashMovement>> _report =
      ReportLoadController<List<CashMovement>>()..addListener(_onReportChanged);
  late DateTime _start;
  late DateTime _end;
  late String _periodLabel;
  DetailPeriod _period = DetailPeriod.initial;
  DateTimeRange? _customRange;
  int _cutoffHour = BusinessDayService.cachedCutoffHour;
  List<CashMovement> get _loaded => _report.data ?? const [];

  @override
  void initState() {
    super.initState();
    _start = widget.start;
    _end = widget.end;
    _periodLabel = widget.periodLabel ?? 'Periodo';
    _load();
  }

  @override
  void dispose() {
    _report.dispose();
    _tabs.dispose();
    super.dispose();
  }

  void _onReportChanged() {
    if (mounted) setState(() {});
  }

  /// [force] salta la caché: tras registrar un movimiento hay que verlo ya.
  void _load({bool force = false}) {
    final businessId = ref.read(authGateViewModelProvider).profile?.businessId;
    if (businessId == null) return;
    final start = _start;
    final end = _end;
    _report.load(
      key: reportCacheKey('cash_movements', businessId, start, end),
      force: force,
      fetch: () => ref
          .read(cashRegisterDataServiceProvider)
          .loadCashMovements(businessId: businessId, start: start, end: end),
    );
  }

  void _applyPeriod(DetailPeriod period) {
    if (period == DetailPeriod.initial) {
      setState(() {
        _period = DetailPeriod.initial;
        _start = widget.start;
        _end = widget.end;
        _periodLabel = widget.periodLabel ?? 'Periodo';
        _load();
      });
      return;
    }
    final range = rangeForDetailPeriod(
      period,
      DateTime.now(),
      cutoffHour: _cutoffHour,
    );
    if (range == null) return;
    setState(() {
      _period = period;
      _start = range.start;
      _end = range.end;
      _periodLabel = labelForDetailPeriod(period);
      _load();
    });
  }

  /// Cambia la hora de corte usada por este reporte y recalcula el período.
  void _applyCutoff(int hour) {
    setState(() => _cutoffHour = hour);
    if (_period == DetailPeriod.custom && _customRange != null) {
      final range = operativeRangeForPickedDays(
        _customRange!,
        cutoffHour: hour,
      );
      setState(() {
        _start = range.start;
        _end = range.end;
        _load();
      });
      return;
    }
    _applyPeriod(_period);
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
    final pickedRange = operativeRangeForPickedDays(
      picked,
      cutoffHour: _cutoffHour,
    );
    final start = pickedRange.start;
    final end = pickedRange.end;
    setState(() {
      _period = DetailPeriod.custom;
      _customRange = picked;
      _start = start;
      _end = end;
      _periodLabel = labelForDetailPeriod(
        DetailPeriod.custom,
        customRange: picked,
      );
      _load();
    });
  }

  List<CashMovement> get _incomes =>
      _loaded.where((m) => m.isIncome).toList(growable: false);
  List<CashMovement> get _expenses =>
      _loaded.where((m) => !m.isIncome).toList(growable: false);

  double get _incomeTotal => _incomes.fold(0.0, (sum, m) => sum + m.amount);
  double get _expenseTotal => _expenses.fold(0.0, (sum, m) => sum + m.amount);

  List<List<String>> _rowsForExport() {
    return [
      for (final m in _loaded)
        [
          m.typeLabel,
          m.createdAt != null ? MangoFormatters.dateTime(m.createdAt!) : '',
          m.reasonLabel ?? '',
          (m.isIncome ? m.amount : -m.amount).toStringAsFixed(2),
          [
            if (m.description != null) 'Nota: ${m.description}',
            if (m.registerName != null) m.registerName!,
            if (m.userName != null) 'Cajero: ${m.userName}',
          ].join(' · '),
        ],
    ];
  }

  Future<void> _exportCsv() async {
    await ReportExportService.exportCsv(
      filename: 'ingresos_egresos_${_periodLabel.replaceAll(' ', '_')}',
      headers: const ['Tipo', 'Fecha', 'Razón', 'Monto', 'Detalle'],
      rows: _rowsForExport(),
      subject: 'Ingresos y egresos · $_periodLabel',
    );
  }

  Future<void> _exportPdf() async {
    await ReportExportService.exportPdf(
      filename: 'ingresos_egresos_${_periodLabel.replaceAll(' ', '_')}',
      title: 'Ingresos y egresos',
      subtitle: 'Periodo: $_periodLabel',
      headers: const ['Tipo', 'Fecha', 'Razón', 'Monto', 'Detalle'],
      rows: _rowsForExport(),
    );
  }

  /// Registrar un movimiento manual (ingreso, retiro o gasto) en una caja
  /// abierta del negocio. Abre en el tipo de la pestaña visible y, al volver
  /// con éxito, recarga el período para que el movimiento aparezca en la lista
  /// y en el neto del encabezado.
  Future<void> _registerMovement() async {
    final businessId = ref.read(authGateViewModelProvider).profile?.businessId;
    if (businessId == null) return;
    final registered = await showCashMovementDialog(
      context: context,
      businessId: businessId,
      initialType: _tabs.index == 0
          ? cashMovementDeposit
          : cashMovementWithdrawal,
    );
    if (registered == null || !mounted) return;
    _load(force: true);
    final label = cashMovementTypeLabel(registered);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '${label[0].toUpperCase()}${label.substring(1)} registrado en caja.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dpi = DpiScale.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ingresos y egresos'),
        centerTitle: false,
        actions: [
          IconButton(
            onPressed: _registerMovement,
            tooltip: 'Registrar movimiento',
            color: MangoThemeFactory.mango,
            icon: const Icon(Icons.add_rounded),
          ),
          ExportMenuButton(
            enabled: !_report.isStale && _loaded.isNotEmpty,
            onExportCsv: _exportCsv,
            onExportPdf: _exportPdf,
          ),
        ],
        bottom: TabBar(
          controller: _tabs,
          indicatorColor: MangoThemeFactory.mango,
          labelColor: MangoThemeFactory.mango,
          tabs: const [
            Tab(icon: Icon(Icons.south_west_rounded), text: 'Ingresos'),
            Tab(icon: Icon(Icons.north_east_rounded), text: 'Egresos'),
          ],
        ),
      ),
      body: Builder(
        builder: (context) {
          return Column(
            children: [
              ReportStaleFade(
                controller: _report,
                child: _Header(
                  periodLabel: _periodLabel,
                  incomeTotal: _incomeTotal,
                  incomeCount: _incomes.length,
                  expenseTotal: _expenseTotal,
                  expenseCount: _expenses.length,
                ),
              ),
              SizedBox(height: dpi.space(8)),
              PeriodFilterBar(
                selected: _period,
                customRange: _customRange,
                initialLabel: widget.periodLabel,
                onSelected: _applyPeriod,
                onPickCustom: _pickCustomRange,
                cutoffHour: _cutoffHour,
                onCutoffChanged: _applyCutoff,
                accent: MangoThemeFactory.success,
              ),
              SizedBox(height: dpi.space(8)),
              Expanded(
                child: ReportBody<List<CashMovement>>(
                  controller: _report,
                  errorMessage: 'No se pudieron cargar los movimientos.',
                  builder: (context, _) => TabBarView(
                    controller: _tabs,
                    children: [
                      _MovementList(
                        items: _incomes,
                        emptyMessage: 'Sin ingresos de caja en este periodo.',
                      ),
                      _MovementList(
                        items: _expenses,
                        emptyMessage: 'Sin egresos de caja en este periodo.',
                      ),
                    ],
                  ),
                ),
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
    required this.periodLabel,
    required this.incomeTotal,
    required this.incomeCount,
    required this.expenseTotal,
    required this.expenseCount,
  });

  final String periodLabel;
  final double incomeTotal;
  final int incomeCount;
  final double expenseTotal;
  final int expenseCount;

  @override
  Widget build(BuildContext context) {
    final dpi = DpiScale.of(context);
    final net = incomeTotal - expenseTotal;
    return Container(
      margin: EdgeInsets.fromLTRB(
        dpi.space(16),
        dpi.space(16),
        dpi.space(16),
        dpi.space(8),
      ),
      padding: EdgeInsets.all(dpi.space(18)),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            MangoThemeFactory.success,
            MangoThemeFactory.success.withValues(alpha: 0.78),
          ],
        ),
        borderRadius: BorderRadius.circular(dpi.radius(20)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.swap_vert_rounded,
                color: Colors.white,
                size: dpi.icon(18),
              ),
              SizedBox(width: dpi.space(6)),
              Text(
                'Ingresos y egresos · $periodLabel',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: dpi.font(12),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          SizedBox(height: dpi.space(10)),
          Text(
            'Neto del periodo',
            style: TextStyle(color: Colors.white70, fontSize: dpi.font(11)),
          ),
          SizedBox(height: dpi.space(2)),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              '${net < 0 ? '−' : ''}${MangoFormatters.currency(net.abs())}',
              style: TextStyle(
                color: Colors.white,
                fontSize: dpi.font(24),
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          SizedBox(height: dpi.space(10)),
          Row(
            children: [
              Expanded(
                child: _MiniStat(
                  label: 'Ingresos',
                  value: '$incomeCount',
                  amount: MangoFormatters.currency(incomeTotal),
                ),
              ),
              Container(
                width: 1,
                height: dpi.scale(28),
                color: Colors.white.withValues(alpha: 0.22),
              ),
              Expanded(
                child: _MiniStat(
                  label: 'Egresos',
                  value: '$expenseCount',
                  amount: MangoFormatters.currency(expenseTotal),
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
  const _MiniStat({
    required this.label,
    required this.value,
    required this.amount,
  });
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
          Text(
            label,
            style: TextStyle(color: Colors.white70, fontSize: dpi.font(10)),
          ),
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

class _MovementList extends StatelessWidget {
  const _MovementList({required this.items, required this.emptyMessage});

  final List<CashMovement> items;
  final String emptyMessage;

  @override
  Widget build(BuildContext context) {
    final dpi = DpiScale.of(context);
    if (items.isEmpty) {
      return Center(
        child: Padding(
          padding: EdgeInsets.all(dpi.space(40)),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.account_balance_wallet_outlined,
                size: dpi.icon(48),
                color: MangoThemeFactory.mutedText(context),
              ),
              SizedBox(height: dpi.space(12)),
              Text(
                emptyMessage,
                style: Theme.of(context).textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }
    return ListView.separated(
      padding: EdgeInsets.fromLTRB(
        dpi.space(16),
        dpi.space(8),
        dpi.space(16),
        dpi.space(16) + MediaQuery.of(context).padding.bottom,
      ),
      itemCount: items.length,
      separatorBuilder: (_, _) => SizedBox(height: dpi.space(8)),
      itemBuilder: (context, index) => _MovementTile(movement: items[index]),
    );
  }
}

class _MovementTile extends StatelessWidget {
  const _MovementTile({required this.movement});

  final CashMovement movement;

  @override
  Widget build(BuildContext context) {
    final dpi = DpiScale.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final m = movement;
    final accent = m.isIncome
        ? MangoThemeFactory.success
        : (m.type == 'expense'
              ? MangoThemeFactory.danger
              : MangoThemeFactory.warning);
    final subtitleParts = <String>[
      m.typeLabel,
      if (m.registerName != null) m.registerName!,
      if (m.userName != null) 'Cajero: ${m.userName}',
      if (m.createdAt != null) MangoFormatters.dateTime(m.createdAt!),
    ];
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
                width: dpi.scale(38),
                height: dpi.scale(38),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: isDark ? 0.2 : 0.12),
                  borderRadius: BorderRadius.circular(dpi.radius(10)),
                ),
                child: Icon(
                  m.isIncome
                      ? Icons.add_circle_outline_rounded
                      : (m.type == 'expense'
                            ? Icons.receipt_long_rounded
                            : Icons.remove_circle_outline_rounded),
                  color: accent,
                  size: dpi.icon(20),
                ),
              ),
              SizedBox(width: dpi.space(12)),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      m.reasonLabel ?? m.typeLabel,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    SizedBox(height: dpi.space(2)),
                    Text(
                      subtitleParts.join(' · '),
                      style: TextStyle(
                        fontSize: dpi.font(11),
                        color: MangoThemeFactory.mutedText(context),
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              SizedBox(width: dpi.space(8)),
              Text(
                '${m.isIncome ? '+' : '−'}${MangoFormatters.currency(m.amount)}',
                style: TextStyle(
                  fontSize: dpi.font(13),
                  fontWeight: FontWeight.w800,
                  color: accent,
                ),
              ),
            ],
          ),
          if (m.description != null) ...[
            SizedBox(height: dpi.space(8)),
            Container(
              width: double.infinity,
              padding: EdgeInsets.all(dpi.space(10)),
              decoration: BoxDecoration(
                color: accent.withValues(alpha: isDark ? 0.1 : 0.06),
                borderRadius: BorderRadius.circular(dpi.radius(10)),
              ),
              child: Text(
                m.description!,
                style: TextStyle(
                  fontSize: dpi.font(11.5),
                  color: MangoThemeFactory.textColor(context),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
