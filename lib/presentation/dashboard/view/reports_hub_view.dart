import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/responsive/dpi_scale.dart';
import '../../theme/theme_data_factory.dart';
import '../viewmodel/dashboard_data_view_model.dart';
import '../widgets/growth_chip.dart';
import 'audit_detail_view.dart';
import 'customer_analytics_view.dart';
import 'daily_sales_report_view.dart';
import 'kpi_detail_views.dart';
import 'modifiers_breakdown_view.dart';

/// Hub that gathers the period-bound analytical reports under one entry,
/// reachable from the side drawer. Inherits the current sales period from
/// the dashboard so each report opens prefilled, then the user can adjust
/// the period inside the individual report.
class ReportsHubView extends ConsumerWidget {
  const ReportsHubView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dpi = DpiScale.of(context);
    final summary = ref.watch(salesDataViewModelProvider).summary;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Reportes'),
        centerTitle: false,
      ),
      body: summary == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: EdgeInsets.fromLTRB(
                  dpi.space(16), dpi.space(16), dpi.space(16), dpi.space(24)),
              children: [
                Text(
                  'Periodo actual: ${periodLabelFor(summary.filter)}',
                  style: TextStyle(
                    fontSize: dpi.font(12),
                    color: MangoThemeFactory.mutedText(context),
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.3,
                  ),
                ),
                SizedBox(height: dpi.space(14)),
                _ReportTile(
                  icon: Icons.insights_rounded,
                  accent: MangoThemeFactory.info,
                  title: 'Ventas',
                  subtitle: 'Tickets, totales y desglose del periodo',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => SalesDetailView(summary: summary),
                    ),
                  ),
                ),
                SizedBox(height: dpi.space(10)),
                _ReportTile(
                  icon: Icons.calendar_month_rounded,
                  accent: MangoThemeFactory.info,
                  title: 'Ventas por día',
                  subtitle: 'Venta diaria, impuestos y total general',
                  onTap: () {
                    final start = summary.periodStart ??
                        DateTime.now().subtract(const Duration(days: 30));
                    final end = summary.periodEnd ?? DateTime.now();
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => DailySalesReportView(
                          start: start,
                          end: end,
                          periodLabel: periodLabelFor(summary.filter),
                        ),
                      ),
                    );
                  },
                ),
                SizedBox(height: dpi.space(10)),
                _ReportTile(
                  icon: Icons.local_fire_department_rounded,
                  accent: MangoThemeFactory.mango,
                  title: 'Productos más vendidos',
                  subtitle: 'Ranking de productos por unidades e ingresos',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => TopProductsDetailView(summary: summary),
                    ),
                  ),
                ),
                SizedBox(height: dpi.space(10)),
                _ReportTile(
                  icon: Icons.people_alt_rounded,
                  accent: MangoThemeFactory.success,
                  title: 'Clientes',
                  subtitle: 'Ranking por gasto · recurrencia · nuevos',
                  onTap: () {
                    final start = summary.periodStart ??
                        DateTime.now().subtract(const Duration(days: 30));
                    final end = summary.periodEnd ?? DateTime.now();
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => CustomerAnalyticsView(
                          start: start,
                          end: end,
                          periodLabel: periodLabelFor(summary.filter),
                        ),
                      ),
                    );
                  },
                ),
                SizedBox(height: dpi.space(10)),
                _ReportTile(
                  icon: Icons.tune_rounded,
                  accent: MangoThemeFactory.info,
                  title: 'Modificadores',
                  subtitle: 'Extras y opciones más vendidas',
                  onTap: () {
                    final start = summary.periodStart ??
                        DateTime.now().subtract(const Duration(days: 30));
                    final end = summary.periodEnd ?? DateTime.now();
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => ModifiersBreakdownView(
                          start: start,
                          end: end,
                          periodLabel: periodLabelFor(summary.filter),
                        ),
                      ),
                    );
                  },
                ),
                SizedBox(height: dpi.space(10)),
                _ReportTile(
                  icon: Icons.gavel_rounded,
                  accent: MangoThemeFactory.danger,
                  title: 'Auditoría',
                  subtitle: 'Anulaciones, pagos cancelados y descuentos',
                  onTap: () {
                    final start = summary.periodStart ??
                        DateTime.now().subtract(const Duration(days: 30));
                    final end = summary.periodEnd ?? DateTime.now();
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => AuditDetailView(
                          start: start,
                          end: end,
                          periodLabel: periodLabelFor(summary.filter),
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
    );
  }
}

class _ReportTile extends StatelessWidget {
  const _ReportTile({
    required this.icon,
    required this.accent,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final Color accent;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final dpi = DpiScale.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(dpi.radius(16)),
      child: Container(
        padding: EdgeInsets.all(dpi.space(16)),
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
                color: accent.withValues(alpha: isDark ? 0.2 : 0.12),
                borderRadius: BorderRadius.circular(dpi.radius(10)),
              ),
              child: Icon(icon, color: accent, size: dpi.icon(22)),
            ),
            SizedBox(width: dpi.space(14)),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context)
                        .textTheme
                        .titleSmall
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  SizedBox(height: dpi.space(2)),
                  Text(
                    subtitle,
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
            Icon(Icons.chevron_right_rounded,
                color: MangoThemeFactory.mutedText(context)),
          ],
        ),
      ),
    );
  }
}
