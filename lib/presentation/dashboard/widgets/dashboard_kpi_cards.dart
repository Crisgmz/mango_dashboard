import 'package:flutter/material.dart';

import '../../../core/formatters/mango_formatters.dart';
import '../../../core/responsive/dpi_scale.dart';
import '../../../domain/dashboard/dashboard_models.dart';
import '../../theme/theme_data_factory.dart';

class DashboardKpiCards extends StatelessWidget {
  const DashboardKpiCards({
    super.key,
    required this.summary,
    this.onSalesTap,
    this.onOrdersTap,
    this.onPendingTap,
    this.onAverageTicketTap,
  });

  final DashboardSummary summary;
  final VoidCallback? onSalesTap;
  final VoidCallback? onOrdersTap;
  final VoidCallback? onPendingTap;
  final VoidCallback? onAverageTicketTap;

  @override
  Widget build(BuildContext context) {
    final changePercent = summary.salesChangePercent;
    final isPositive = changePercent >= 0;

    return LayoutBuilder(
      builder: (context, constraints) {
        final crossAxisCount = constraints.maxWidth > 600 ? 4 : 2;
        final childAspectRatio = constraints.maxWidth > 600 ? 1.6 : 1.05;

        return GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: crossAxisCount,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: childAspectRatio,
          children: [
            _KpiCard(
              label: 'Ventas del día',
              value: MangoFormatters.currency(summary.totalSales),
              icon: Icons.trending_up_rounded,
              color: MangoThemeFactory.success,
              accentBackground: true,
              subtitle: changePercent == 0
                  ? 'Sin datos de ayer'
                  : '${isPositive ? '+' : ''}${changePercent.toStringAsFixed(1)}% vs ayer',
              subtitleColor: Colors.white70,
              onTap: onSalesTap,
            ),
            _KpiCard(
              label: 'Órdenes',
              value: MangoFormatters.number(summary.totalTickets),
              icon: Icons.receipt_long_rounded,
              color: MangoThemeFactory.mango,
              accentBackground: true,
              subtitle: '${MangoFormatters.number(summary.activeOrders)} activas',
              onTap: onOrdersTap,
            ),
            _KpiCard(
              label: 'Por Cobrar',
              value: MangoFormatters.currency(summary.pendingAmount),
              icon: Icons.schedule_rounded,
              color: MangoThemeFactory.warning,
              accentBackground: false,
              subtitle: '${MangoFormatters.number(summary.activeOrders)} abiertas',
              onTap: onPendingTap,
            ),
            _KpiCard(
              label: 'Ticket Promedio',
              value: MangoFormatters.currency(summary.averageTicket),
              icon: Icons.shopping_bag_rounded,
              color: MangoThemeFactory.info,
              accentBackground: false,
              subtitle: 'Por completada',
              onTap: onAverageTicketTap,
            ),
          ],
        );
      },
    );
  }
}

class _KpiCard extends StatelessWidget {
  const _KpiCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    required this.accentBackground,
    this.subtitle,
    this.subtitleColor,
    this.onTap,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final bool accentBackground;
  final String? subtitle;
  final Color? subtitleColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final dpi = DpiScale.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = accentBackground ? color : MangoThemeFactory.cardColor(context);
    final textColor = accentBackground ? Colors.white : MangoThemeFactory.textColor(context);
    final mutedColor = accentBackground
        ? Colors.white.withValues(alpha: 0.7)
        : MangoThemeFactory.mutedText(context);
    final iconBg = accentBackground
        ? Colors.white.withValues(alpha: 0.2)
        : color.withValues(alpha: isDark ? 0.2 : 0.12);
    final iconColor = accentBackground ? Colors.white : color;

    final content = Container(
      padding: EdgeInsets.symmetric(horizontal: dpi.space(16), vertical: dpi.space(14)),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(dpi.radius(16)),
        border: accentBackground ? null : Border.all(color: MangoThemeFactory.borderColor(context)),
        boxShadow: [
          BoxShadow(
            color: accentBackground
                ? color.withValues(alpha: 0.3)
                : Colors.black.withValues(alpha: isDark ? 0.2 : 0.04),
            blurRadius: accentBackground ? 10 : 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: dpi.scale(36),
            height: dpi.scale(36),
            decoration: BoxDecoration(
              color: iconBg,
              borderRadius: BorderRadius.circular(dpi.radius(10)),
            ),
            child: Icon(icon, color: iconColor, size: dpi.icon(20)),
          ),
          const Spacer(),
          Text(
            label,
            style: TextStyle(
              fontSize: dpi.font(12),
              fontWeight: FontWeight.w500,
              color: mutedColor,
              letterSpacing: -0.2,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          SizedBox(height: dpi.space(2)),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: TextStyle(
                fontSize: dpi.font(23),
                fontWeight: FontWeight.w800,
                color: textColor,
                letterSpacing: -0.5,
              ),
            ),
          ),
          if (subtitle != null) ...[
            SizedBox(height: dpi.space(1)),
            Text(
              subtitle!,
              style: TextStyle(
                fontSize: dpi.font(11),
                fontWeight: FontWeight.w500,
                color: subtitleColor ?? mutedColor,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          const Spacer(flex: 1),
        ],
      ),
    );

    if (onTap == null) return content;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(dpi.radius(16)),
      splashColor: (accentBackground ? Colors.white : color).withValues(alpha: 0.15),
      highlightColor: (accentBackground ? Colors.white : color).withValues(alpha: 0.08),
      child: content,
    );
  }
}
