import 'package:flutter/material.dart';

import '../../../core/responsive/dpi_scale.dart';
import '../../../domain/dashboard/dashboard_models.dart';
import '../../theme/theme_data_factory.dart';

/// Pill-shaped chip showing % change vs a previous period (e.g. "▲ 12.5%").
/// Renders nothing if there's no baseline (current or previous is zero).
class GrowthChip extends StatelessWidget {
  const GrowthChip({
    super.key,
    required this.current,
    required this.previous,
    this.compact = false,
    this.onLight = false,
  });

  /// Compact variant: smaller padding/font, no label, just arrow + %.
  final bool compact;

  /// True when chip is rendered on a light/white card; false on accent/dark backgrounds.
  /// Drives whether the chip is opaque (better contrast on accent) or tinted (cleaner on cards).
  final bool onLight;

  final double current;
  final double previous;

  @override
  Widget build(BuildContext context) {
    final dpi = DpiScale.of(context);

    if (previous == 0 && current == 0) return const SizedBox.shrink();
    final hasBaseline = previous != 0;
    final pct = hasBaseline ? ((current - previous) / previous) * 100 : 0;
    final isPositive = pct >= 0;

    final color = !hasBaseline
        ? MangoThemeFactory.mutedText(context)
        : isPositive
            ? MangoThemeFactory.success
            : MangoThemeFactory.danger;

    final icon = !hasBaseline
        ? Icons.remove_rounded
        : isPositive
            ? Icons.trending_up_rounded
            : Icons.trending_down_rounded;

    final label = !hasBaseline
        ? 'Nuevo'
        : '${isPositive ? '+' : ''}${pct.toStringAsFixed(1)}%';

    final bg = onLight ? color.withValues(alpha: 0.12) : Colors.white.withValues(alpha: 0.22);
    final fg = onLight ? color : Colors.white;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: dpi.space(compact ? 6 : 8),
        vertical: dpi.space(compact ? 2 : 3),
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(dpi.radius(20)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: dpi.icon(compact ? 11 : 13), color: fg),
          SizedBox(width: dpi.space(3)),
          Text(
            label,
            style: TextStyle(
              fontSize: dpi.font(compact ? 10 : 11),
              fontWeight: FontWeight.w800,
              color: fg,
            ),
          ),
        ],
      ),
    );
  }
}

/// Returns a localized label like "vs ayer" / "vs mes pasado" for the chosen filter.
String comparisonLabelFor(SalesDateFilter filter) {
  switch (filter) {
    case SalesDateFilter.today:
      return 'vs ayer';
    case SalesDateFilter.yesterday:
      return 'vs anteayer';
    case SalesDateFilter.week:
      return 'vs semana anterior';
    case SalesDateFilter.month:
      return 'vs mes anterior';
    case SalesDateFilter.lastMonth:
      return 'vs hace 2 meses';
    case SalesDateFilter.last3Months:
      return 'vs trimestre anterior';
    case SalesDateFilter.custom:
      return 'vs periodo previo';
  }
}
