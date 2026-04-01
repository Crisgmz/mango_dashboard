import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../core/responsive/dpi_scale.dart';
import '../../../domain/dashboard/dashboard_models.dart';
import '../../theme/theme_data_factory.dart';

enum ChartFilter { today, weekly, monthly }

class DashboardSalesChart extends StatefulWidget {
  const DashboardSalesChart({super.key, required this.hourlySales});

  final List<HourlySale> hourlySales;

  @override
  State<DashboardSalesChart> createState() => _DashboardSalesChartState();
}

class _DashboardSalesChartState extends State<DashboardSalesChart> {
  ChartFilter _filter = ChartFilter.today;

  @override
  Widget build(BuildContext context) {
    final dpi = DpiScale.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(dpi.space(18)),
      decoration: BoxDecoration(
        color: MangoThemeFactory.cardColor(context),
        borderRadius: BorderRadius.circular(dpi.radius(16)),
        border: Border.all(color: MangoThemeFactory.borderColor(context)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.04),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: dpi.space(8),
            runSpacing: dpi.space(8),
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Ventas por hora',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  SizedBox(height: dpi.space(2)),
                  Text(
                    'Flujo de ventas durante el día',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
              _FilterChips(
                selected: _filter,
                onChanged: (f) => setState(() => _filter = f),
              ),
            ],
          ),
          SizedBox(height: dpi.space(20)),
          SizedBox(
            height: dpi.scale(200),
            child: widget.hourlySales.isEmpty
                ? Center(
                    child: Text(
                      'Sin datos de ventas aún',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  )
                : _buildChart(context),
          ),
        ],
      ),
    );
  }

  Widget _buildChart(BuildContext context) {
    final dpi = DpiScale.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final spots = widget.hourlySales
        .map((s) => FlSpot(s.hour.toDouble(), s.amount))
        .toList();

    final maxY = spots.fold<double>(0, (prev, s) => s.y > prev ? s.y : prev);

    return LineChart(
      LineChartData(
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: maxY > 0 ? maxY / 4 : 1,
          getDrawingHorizontalLine: (value) => FlLine(
            color: MangoThemeFactory.borderColor(context),
            strokeWidth: 1,
          ),
        ),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: dpi.scale(50),
              getTitlesWidget: (value, meta) => Text(
                _shortCurrency(value),
                style: TextStyle(
                  fontSize: dpi.font(10),
                  color: MangoThemeFactory.mutedText(context),
                ),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              interval: 2,
              getTitlesWidget: (value, meta) {
                final hour = value.toInt();
                if (hour < 0 || hour > 23) return const SizedBox.shrink();
                final label = hour == 0
                    ? '12am'
                    : hour < 12
                        ? '${hour}am'
                        : hour == 12
                            ? '12pm'
                            : '${hour - 12}pm';
                return Text(
                  label,
                  style: TextStyle(
                    fontSize: dpi.font(10),
                    color: MangoThemeFactory.mutedText(context),
                  ),
                );
              },
            ),
          ),
        ),
        borderData: FlBorderData(show: false),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            curveSmoothness: 0.3,
            color: MangoThemeFactory.success,
            barWidth: 3,
            isStrokeCapRound: true,
            dotData: FlDotData(
              show: true,
              getDotPainter: (spot, percent, barData, index) =>
                  FlDotCirclePainter(
                radius: dpi.scale(4),
                color: MangoThemeFactory.success,
                strokeWidth: 2,
                strokeColor: isDark ? const Color(0xFF1A1D21) : Colors.white,
              ),
            ),
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  MangoThemeFactory.success.withValues(alpha: 0.3),
                  MangoThemeFactory.success.withValues(alpha: 0.0),
                ],
              ),
            ),
          ),
        ],
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (_) => isDark ? const Color(0xFF2B3138) : Colors.white,
            getTooltipItems: (spots) => spots.map((s) {
              return LineTooltipItem(
                'RD\$ ${s.y.toStringAsFixed(2)}',
                TextStyle(
                  color: MangoThemeFactory.success,
                  fontWeight: FontWeight.w700,
                  fontSize: dpi.font(13),
                ),
              );
            }).toList(),
          ),
        ),
      ),
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeInOut,
    );
  }

  String _shortCurrency(double value) {
    if (value >= 1000) return '${(value / 1000).toStringAsFixed(1)}k';
    return value.toStringAsFixed(0);
  }
}

class _FilterChips extends StatelessWidget {
  const _FilterChips({required this.selected, required this.onChanged});

  final ChartFilter selected;
  final ValueChanged<ChartFilter> onChanged;

  @override
  Widget build(BuildContext context) {
    final dpi = DpiScale.of(context);

    return Container(
      padding: EdgeInsets.all(dpi.space(3)),
      decoration: BoxDecoration(
        color: MangoThemeFactory.altSurface(context),
        borderRadius: BorderRadius.circular(dpi.radius(10)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: ChartFilter.values.map((f) {
          final isSelected = f == selected;
          return GestureDetector(
            onTap: () => onChanged(f),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: EdgeInsets.symmetric(horizontal: dpi.space(10), vertical: dpi.space(5)),
              decoration: BoxDecoration(
                color: isSelected ? MangoThemeFactory.success : Colors.transparent,
                borderRadius: BorderRadius.circular(dpi.radius(8)),
              ),
              child: Text(
                _label(f),
                style: TextStyle(
                  fontSize: dpi.font(11),
                  fontWeight: FontWeight.w600,
                  color: isSelected ? Colors.white : MangoThemeFactory.mutedText(context),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  String _label(ChartFilter f) {
    switch (f) {
      case ChartFilter.today:
        return 'Hoy';
      case ChartFilter.weekly:
        return 'Semana';
      case ChartFilter.monthly:
        return 'Mes';
    }
  }
}
