import 'package:flutter/material.dart';

import '../../../core/formatters/mango_formatters.dart';
import '../../../core/responsive/dpi_scale.dart';
import '../../theme/theme_data_factory.dart';

/// Projects the end-of-month total at the current pace, compares it to last
/// month, and shows progress through the month.
///
/// Inputs:
///   - [currentMonthSales]: month-to-date total
///   - [previousMonthSales]: previous month's total (for comparison)
///   - [now]: current date (testable; defaults to DateTime.now())
class MonthProjectionCard extends StatelessWidget {
  const MonthProjectionCard({
    super.key,
    required this.currentMonthSales,
    required this.previousMonthSales,
    DateTime? now,
  }) : _nowOverride = now;

  final double currentMonthSales;
  final double previousMonthSales;
  final DateTime? _nowOverride;

  @override
  Widget build(BuildContext context) {
    final dpi = DpiScale.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final now = _nowOverride ?? DateTime.now();

    final daysInMonth = DateTime(now.year, now.month + 1, 0).day;
    final daysElapsed = now.day; // 1..daysInMonth
    final daysRemaining = (daysInMonth - daysElapsed).clamp(0, daysInMonth);
    final monthProgress = daysElapsed / daysInMonth;

    final pace = daysElapsed > 0 ? currentMonthSales / daysElapsed : 0.0;
    final projection = pace * daysInMonth;

    final hasPrev = previousMonthSales > 0;
    final pctVsPrev = hasPrev ? ((projection - previousMonthSales) / previousMonthSales) * 100 : 0.0;
    final ahead = pctVsPrev >= 0;

    final statusColor = !hasPrev
        ? MangoThemeFactory.info
        : ahead
            ? MangoThemeFactory.success
            : MangoThemeFactory.warning;

    return Container(
      padding: EdgeInsets.all(dpi.space(18)),
      decoration: BoxDecoration(
        color: MangoThemeFactory.cardColor(context),
        borderRadius: BorderRadius.circular(dpi.radius(18)),
        border: Border.all(color: MangoThemeFactory.borderColor(context)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.18 : 0.04),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: dpi.scale(36),
                height: dpi.scale(36),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: isDark ? 0.2 : 0.12),
                  borderRadius: BorderRadius.circular(dpi.radius(10)),
                ),
                child: Icon(Icons.insights_rounded, color: statusColor, size: dpi.icon(20)),
              ),
              SizedBox(width: dpi.space(10)),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Proyección de fin de mes',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    Text(
                      'Al ritmo actual',
                      style: TextStyle(fontSize: dpi.font(11), color: MangoThemeFactory.mutedText(context)),
                    ),
                  ],
                ),
              ),
              if (hasPrev)
                Container(
                  padding: EdgeInsets.symmetric(horizontal: dpi.space(8), vertical: dpi.space(3)),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(dpi.radius(20)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        ahead ? Icons.trending_up_rounded : Icons.trending_down_rounded,
                        size: dpi.icon(13),
                        color: statusColor,
                      ),
                      SizedBox(width: dpi.space(3)),
                      Text(
                        '${ahead ? '+' : ''}${pctVsPrev.toStringAsFixed(1)}%',
                        style: TextStyle(
                          fontSize: dpi.font(11),
                          fontWeight: FontWeight.w800,
                          color: statusColor,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          SizedBox(height: dpi.space(14)),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              MangoFormatters.currency(projection),
              style: TextStyle(
                fontSize: dpi.font(28),
                fontWeight: FontWeight.w800,
                color: statusColor,
                letterSpacing: -0.5,
              ),
            ),
          ),
          SizedBox(height: dpi.space(2)),
          Text(
            hasPrev
                ? 'vs ${MangoFormatters.currency(previousMonthSales)} el mes pasado'
                : 'sin datos del mes anterior',
            style: TextStyle(fontSize: dpi.font(11), color: MangoThemeFactory.mutedText(context)),
          ),
          SizedBox(height: dpi.space(14)),
          // Month progress bar.
          Stack(
            children: [
              Container(
                height: dpi.space(8),
                decoration: BoxDecoration(
                  color: MangoThemeFactory.borderColor(context),
                  borderRadius: BorderRadius.circular(dpi.radius(4)),
                ),
              ),
              FractionallySizedBox(
                widthFactor: monthProgress.clamp(0.0, 1.0),
                child: Container(
                  height: dpi.space(8),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [statusColor, statusColor.withValues(alpha: 0.7)],
                    ),
                    borderRadius: BorderRadius.circular(dpi.radius(4)),
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: dpi.space(8)),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Día $daysElapsed de $daysInMonth',
                style: TextStyle(fontSize: dpi.font(11), color: MangoThemeFactory.mutedText(context)),
              ),
              Text(
                daysRemaining == 0
                    ? 'último día'
                    : '$daysRemaining ${daysRemaining == 1 ? 'día restante' : 'días restantes'}',
                style: TextStyle(fontSize: dpi.font(11), color: MangoThemeFactory.mutedText(context), fontWeight: FontWeight.w600),
              ),
            ],
          ),
          SizedBox(height: dpi.space(10)),
          Row(
            children: [
              Expanded(
                child: _StatTile(
                  label: 'Vendido',
                  value: MangoFormatters.currency(currentMonthSales),
                  color: MangoThemeFactory.textColor(context),
                ),
              ),
              Container(
                width: 1,
                height: dpi.scale(28),
                color: MangoThemeFactory.borderColor(context),
              ),
              Expanded(
                child: _StatTile(
                  label: 'Promedio/día',
                  value: MangoFormatters.currency(pace),
                  color: MangoThemeFactory.textColor(context),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({required this.label, required this.value, required this.color});
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final dpi = DpiScale.of(context);
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: dpi.space(8), vertical: dpi.space(2)),
      child: Column(
        children: [
          Text(
            label,
            style: TextStyle(fontSize: dpi.font(10), color: MangoThemeFactory.mutedText(context)),
          ),
          SizedBox(height: dpi.space(2)),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              style: TextStyle(fontSize: dpi.font(13), fontWeight: FontWeight.w800, color: color),
            ),
          ),
        ],
      ),
    );
  }
}
