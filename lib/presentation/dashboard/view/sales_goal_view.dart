import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/di/providers.dart';
import '../../../core/formatters/mango_formatters.dart';
import '../../../core/responsive/dpi_scale.dart';
import '../../../data/dashboard/goal_projection.dart';
import '../../../data/dashboard/sales_goal_service.dart';
import '../../auth/viewmodel/auth_gate_view_model.dart';
import '../../theme/theme_data_factory.dart';

const _monthsEs = [
  'Enero', 'Febrero', 'Marzo', 'Abril', 'Mayo', 'Junio',
  'Julio', 'Agosto', 'Septiembre', 'Octubre', 'Noviembre', 'Diciembre',
];

typedef _Loaded = ({double? goal, double actual});

/// "Meta": the owner sets a monthly sales target and tracks progress vs. actual
/// (month-to-date), with a run-rate projection of where the month will close.
class SalesGoalView extends ConsumerStatefulWidget {
  const SalesGoalView({super.key});

  @override
  ConsumerState<SalesGoalView> createState() => _SalesGoalViewState();
}

class _SalesGoalViewState extends ConsumerState<SalesGoalView> {
  static const _service = SalesGoalService();

  late int _year;
  late int _month;
  late Future<_Loaded> _future;
  _Loaded _loaded = (goal: null, actual: 0.0);

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _year = now.year;
    _month = now.month;
    _future = _load();
  }

  int get _daysInMonth => DateTime(_year, _month + 1, 0).day;
  bool get _isCurrentMonth {
    final now = DateTime.now();
    return _year == now.year && _month == now.month;
  }

  int get _dayOfMonth => _isCurrentMonth ? DateTime.now().day : _daysInMonth;

  Future<_Loaded> _load() async {
    final profile = ref.read(authGateViewModelProvider).profile;
    final businessId = profile?.businessId;
    if (businessId == null) return (goal: null, actual: 0.0);

    final goal = await _service.getGoal(businessId, _year, _month);
    final monthStart = DateTime(_year, _month, 1);
    final now = DateTime.now();
    final end = _isCurrentMonth
        ? DateTime(now.year, now.month, now.day).add(const Duration(days: 1))
        : DateTime(_year, _month + 1, 1);
    final report = await ref
        .read(dashboardDataServiceProvider)
        .loadDailySales(businessId: businessId, start: monthStart, end: end);

    final loaded = (goal: goal, actual: report.grossTotal);
    if (mounted) setState(() => _loaded = loaded);
    return loaded;
  }

  Future<void> _editGoal() async {
    final controller = TextEditingController(
        text: _loaded.goal == null ? '' : _loaded.goal!.toStringAsFixed(0));
    final amount = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Meta de ${_monthsEs[_month - 1]}'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            prefixText: 'RD\$ ',
            hintText: '1500000',
            labelText: 'Objetivo de ventas',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          FilledButton(
            onPressed: () {
              final cleaned = controller.text.replaceAll(RegExp(r'[^0-9.]'), '');
              Navigator.pop(ctx, double.tryParse(cleaned) ?? 0);
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
    if (amount == null) return; // cancelled
    final profile = ref.read(authGateViewModelProvider).profile;
    final businessId = profile?.businessId;
    if (businessId == null) return;
    await _service.setGoal(businessId, _year, _month, amount);
    if (mounted) setState(() => _future = _load());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Meta de venta'),
        centerTitle: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_rounded),
            tooltip: 'Editar meta',
            onPressed: _editGoal,
          ),
        ],
      ),
      body: FutureBuilder<_Loaded>(
        future: _future,
        builder: (context, snapshot) {
          final dpi = DpiScale.of(context);
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final data = snapshot.data ?? _loaded;
          return ListView(
            physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
            padding: EdgeInsets.fromLTRB(dpi.space(16), dpi.space(16), dpi.space(16),
                dpi.space(16) + MediaQuery.of(context).padding.bottom),
            children: [
              if (data.goal == null)
                _NoGoalCard(
                  monthLabel: '${_monthsEs[_month - 1]} $_year',
                  actual: data.actual,
                  onSet: _editGoal,
                )
              else
                ..._goalContent(context, data.goal!, data.actual),
            ],
          );
        },
      ),
    );
  }

  List<Widget> _goalContent(BuildContext context, double goal, double actual) {
    final dpi = DpiScale.of(context);
    final p = projectGoal(
      goal: goal,
      actual: actual,
      dayOfMonth: _dayOfMonth,
      daysInMonth: _daysInMonth,
    );
    return [
      _ProgressHeader(
        monthLabel: '${_monthsEs[_month - 1]} $_year',
        goal: goal,
        actual: actual,
        progress: p.progress,
        onTrack: p.onTrack,
      ),
      SizedBox(height: dpi.space(14)),
      Row(
        children: [
          Expanded(
            child: _Kpi(
              icon: Icons.trending_up_rounded,
              label: 'Proyección de cierre',
              value: MangoFormatters.currency(p.projected),
              accent: p.onTrack ? MangoThemeFactory.success : MangoThemeFactory.danger,
            ),
          ),
          SizedBox(width: dpi.space(10)),
          Expanded(
            child: _Kpi(
              icon: Icons.flag_outlined,
              label: 'Falta para la meta',
              value: MangoFormatters.currency(p.remaining),
              accent: MangoThemeFactory.info,
            ),
          ),
        ],
      ),
      SizedBox(height: dpi.space(10)),
      Row(
        children: [
          Expanded(
            child: _Kpi(
              icon: Icons.today_rounded,
              label: 'Meta diaria',
              value: MangoFormatters.currency(p.dailyTarget),
              accent: MangoThemeFactory.info,
            ),
          ),
          SizedBox(width: dpi.space(10)),
          Expanded(
            child: _Kpi(
              icon: Icons.speed_rounded,
              label: 'Ritmo actual/día',
              value: MangoFormatters.currency(p.dailyPace),
              accent: p.dailyPace >= p.dailyTarget
                  ? MangoThemeFactory.success
                  : MangoThemeFactory.warning,
            ),
          ),
        ],
      ),
      SizedBox(height: dpi.space(14)),
      _PaceNote(onTrack: p.onTrack, projected: p.projected, goal: goal),
    ];
  }
}

class _ProgressHeader extends StatelessWidget {
  const _ProgressHeader({
    required this.monthLabel,
    required this.goal,
    required this.actual,
    required this.progress,
    required this.onTrack,
  });
  final String monthLabel;
  final double goal;
  final double actual;
  final double progress;
  final bool onTrack;

  @override
  Widget build(BuildContext context) {
    final dpi = DpiScale.of(context);
    final accent = onTrack ? MangoThemeFactory.success : MangoThemeFactory.mango;
    final pct = (progress * 100);
    return Container(
      padding: EdgeInsets.all(dpi.space(18)),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [accent, accent.withValues(alpha: 0.78)]),
        borderRadius: BorderRadius.circular(dpi.radius(20)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.emoji_events_rounded, color: Colors.white, size: dpi.icon(18)),
              SizedBox(width: dpi.space(6)),
              Text('Meta · $monthLabel',
                  style: TextStyle(
                      color: Colors.white, fontSize: dpi.font(12), fontWeight: FontWeight.w600)),
            ],
          ),
          SizedBox(height: dpi.space(12)),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              MangoFormatters.currency(actual),
              style: TextStyle(
                  color: Colors.white, fontSize: dpi.font(26), fontWeight: FontWeight.w800),
            ),
          ),
          Text('de ${MangoFormatters.currency(goal)} · ${pct.toStringAsFixed(0)}%',
              style: TextStyle(color: Colors.white70, fontSize: dpi.font(12))),
          SizedBox(height: dpi.space(12)),
          ClipRRect(
            borderRadius: BorderRadius.circular(dpi.radius(6)),
            child: LinearProgressIndicator(
              value: progress.clamp(0.0, 1.0),
              minHeight: dpi.scale(8),
              backgroundColor: Colors.white.withValues(alpha: 0.25),
              valueColor: const AlwaysStoppedAnimation(Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}

class _Kpi extends StatelessWidget {
  const _Kpi({required this.icon, required this.label, required this.value, required this.accent});
  final IconData icon;
  final String label;
  final String value;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final dpi = DpiScale.of(context);
    return Container(
      padding: EdgeInsets.all(dpi.space(12)),
      decoration: BoxDecoration(
        color: MangoThemeFactory.cardColor(context),
        borderRadius: BorderRadius.circular(dpi.radius(14)),
        border: Border.all(color: MangoThemeFactory.borderColor(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: dpi.icon(18), color: accent),
          SizedBox(height: dpi.space(8)),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value,
                style: TextStyle(
                    fontSize: dpi.font(15),
                    fontWeight: FontWeight.w800,
                    color: MangoThemeFactory.textColor(context))),
          ),
          SizedBox(height: dpi.space(2)),
          Text(label,
              style: TextStyle(fontSize: dpi.font(10), color: MangoThemeFactory.mutedText(context))),
        ],
      ),
    );
  }
}

class _PaceNote extends StatelessWidget {
  const _PaceNote({required this.onTrack, required this.projected, required this.goal});
  final bool onTrack;
  final double projected;
  final double goal;

  @override
  Widget build(BuildContext context) {
    final dpi = DpiScale.of(context);
    final color = onTrack ? MangoThemeFactory.success : MangoThemeFactory.danger;
    final diff = (projected - goal).abs();
    final msg = onTrack
        ? 'Al ritmo actual, cerrarías el mes ${MangoFormatters.currency(diff)} por encima de la meta.'
        : 'Al ritmo actual, te quedarías ${MangoFormatters.currency(diff)} por debajo de la meta.';
    return Container(
      padding: EdgeInsets.all(dpi.space(14)),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(dpi.radius(14)),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(onTrack ? Icons.check_circle_rounded : Icons.error_outline_rounded,
              color: color, size: dpi.icon(20)),
          SizedBox(width: dpi.space(10)),
          Expanded(
            child: Text(msg,
                style: TextStyle(
                    fontSize: dpi.font(12), fontWeight: FontWeight.w600, color: color)),
          ),
        ],
      ),
    );
  }
}

class _NoGoalCard extends StatelessWidget {
  const _NoGoalCard({required this.monthLabel, required this.actual, required this.onSet});
  final String monthLabel;
  final double actual;
  final VoidCallback onSet;

  @override
  Widget build(BuildContext context) {
    final dpi = DpiScale.of(context);
    return Container(
      padding: EdgeInsets.all(dpi.space(20)),
      decoration: BoxDecoration(
        color: MangoThemeFactory.cardColor(context),
        borderRadius: BorderRadius.circular(dpi.radius(16)),
        border: Border.all(color: MangoThemeFactory.borderColor(context)),
      ),
      child: Column(
        children: [
          Icon(Icons.flag_circle_rounded, size: dpi.icon(48), color: MangoThemeFactory.mango),
          SizedBox(height: dpi.space(12)),
          Text('Sin meta para $monthLabel',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
          SizedBox(height: dpi.space(6)),
          Text('Llevas ${MangoFormatters.currency(actual)} este mes. Define un objetivo para seguir tu progreso y proyección.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: dpi.font(12), color: MangoThemeFactory.mutedText(context))),
          SizedBox(height: dpi.space(16)),
          FilledButton.icon(
            onPressed: onSet,
            icon: const Icon(Icons.add_rounded),
            label: const Text('Definir meta'),
          ),
        ],
      ),
    );
  }
}
