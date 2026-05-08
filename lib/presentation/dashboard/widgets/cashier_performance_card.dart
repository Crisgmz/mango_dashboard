import 'package:flutter/material.dart';

import '../../../core/formatters/mango_formatters.dart';
import '../../../core/responsive/dpi_scale.dart';
import '../../../domain/dashboard/dashboard_models.dart';
import '../../theme/theme_data_factory.dart';

/// Lists cajeros with their period totals (ventas procesadas, tickets, mesas)
/// ranked by sales. Mirrors `WaiterPerformanceCard` but for `processed_by`.
class CashierPerformanceCard extends StatelessWidget {
  const CashierPerformanceCard({
    super.key,
    required this.cashiers,
    this.onItemTap,
    this.maxItems = 6,
  });

  final List<CashierPerformance> cashiers;
  final ValueChanged<CashierPerformance>? onItemTap;
  final int maxItems;

  @override
  Widget build(BuildContext context) {
    final dpi = DpiScale.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (cashiers.isEmpty) return const SizedBox.shrink();

    final shown = cashiers.take(maxItems).toList();
    final maxSales = shown.first.totalSales;

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
                  color: MangoThemeFactory.info.withValues(alpha: isDark ? 0.2 : 0.12),
                  borderRadius: BorderRadius.circular(dpi.radius(10)),
                ),
                child: Icon(Icons.point_of_sale_rounded, color: MangoThemeFactory.info, size: dpi.icon(20)),
              ),
              SizedBox(width: dpi.space(10)),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Rendimiento por cajero',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    Text(
                      'Top ${shown.length} del periodo',
                      style: TextStyle(fontSize: dpi.font(11), color: MangoThemeFactory.mutedText(context)),
                    ),
                  ],
                ),
              ),
              if (cashiers.length > shown.length)
                Container(
                  padding: EdgeInsets.symmetric(horizontal: dpi.space(8), vertical: dpi.space(3)),
                  decoration: BoxDecoration(
                    color: MangoThemeFactory.info.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(dpi.radius(20)),
                  ),
                  child: Text(
                    '${cashiers.length} totales',
                    style: TextStyle(
                      fontSize: dpi.font(10),
                      fontWeight: FontWeight.w800,
                      color: MangoThemeFactory.info,
                    ),
                  ),
                ),
            ],
          ),
          SizedBox(height: dpi.space(14)),
          for (var i = 0; i < shown.length; i++) ...[
            _CashierRow(
              rank: i + 1,
              data: shown[i],
              maxSales: maxSales,
              onTap: onItemTap == null ? null : () => onItemTap!(shown[i]),
            ),
            if (i < shown.length - 1) SizedBox(height: dpi.space(12)),
          ],
        ],
      ),
    );
  }
}

class _CashierRow extends StatelessWidget {
  const _CashierRow({
    required this.rank,
    required this.data,
    required this.maxSales,
    this.onTap,
  });

  final int rank;
  final CashierPerformance data;
  final double maxSales;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final dpi = DpiScale.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final share = maxSales == 0 ? 0.0 : (data.totalSales / maxSales);

    final rankColor = rank == 1
        ? MangoThemeFactory.info
        : rank == 2
            ? MangoThemeFactory.warning
            : rank == 3
                ? MangoThemeFactory.mango
                : MangoThemeFactory.mutedText(context);

    final initials = _initialsFor(data.name);

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: dpi.scale(34),
                  height: dpi.scale(34),
                  decoration: BoxDecoration(
                    color: rankColor.withValues(alpha: isDark ? 0.2 : 0.12),
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    initials,
                    style: TextStyle(
                      fontSize: dpi.font(12),
                      fontWeight: FontWeight.w800,
                      color: rankColor,
                    ),
                  ),
                ),
                Positioned(
                  bottom: -2,
                  right: -2,
                  child: Container(
                    width: dpi.scale(16),
                    height: dpi.scale(16),
                    decoration: BoxDecoration(
                      color: rankColor,
                      shape: BoxShape.circle,
                      border: Border.all(color: MangoThemeFactory.cardColor(context), width: 1.5),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      '$rank',
                      style: TextStyle(
                        fontSize: dpi.font(8),
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(width: dpi.space(12)),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    data.name,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  SizedBox(height: dpi.space(2)),
                  Text(
                    '${data.tablesCount} ${data.tablesCount == 1 ? 'mesa' : 'mesas'} · ${data.ticketCount} ${data.ticketCount == 1 ? 'pago' : 'pagos'} · prom. ${MangoFormatters.currency(data.averageTicket)}',
                    style: TextStyle(fontSize: dpi.font(11), color: MangoThemeFactory.mutedText(context)),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            SizedBox(width: dpi.space(8)),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                MangoFormatters.currency(data.totalSales),
                style: TextStyle(
                  fontSize: dpi.font(14),
                  fontWeight: FontWeight.w800,
                  color: MangoThemeFactory.info,
                ),
              ),
            ),
            if (onTap != null) ...[
              SizedBox(width: dpi.space(4)),
              Icon(Icons.chevron_right_rounded,
                  size: dpi.icon(18), color: MangoThemeFactory.mutedText(context)),
            ],
          ],
        ),
        SizedBox(height: dpi.space(8)),
        Padding(
          padding: EdgeInsets.only(left: dpi.space(46)),
          child: Stack(
            children: [
              Container(
                height: dpi.space(6),
                decoration: BoxDecoration(
                  color: MangoThemeFactory.borderColor(context),
                  borderRadius: BorderRadius.circular(dpi.radius(3)),
                ),
              ),
              FractionallySizedBox(
                widthFactor: share.clamp(0.0, 1.0),
                child: Container(
                  height: dpi.space(6),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [rankColor, rankColor.withValues(alpha: 0.7)],
                    ),
                    borderRadius: BorderRadius.circular(dpi.radius(3)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );

    if (onTap == null) return content;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(dpi.radius(10)),
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: dpi.space(2)),
        child: content,
      ),
    );
  }

  static String _initialsFor(String name) {
    final cleaned = name.trim();
    if (cleaned.isEmpty) return '?';
    final parts = cleaned.split(RegExp(r'\s+'));
    if (parts.length == 1) return parts[0][0].toUpperCase();
    return (parts[0][0] + parts[1][0]).toUpperCase();
  }
}
