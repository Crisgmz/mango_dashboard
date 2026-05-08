import 'package:flutter/material.dart';

import '../../../core/formatters/mango_formatters.dart';
import '../../../core/responsive/dpi_scale.dart';
import '../../../domain/dashboard/dashboard_models.dart';
import '../../theme/theme_data_factory.dart';

/// Projects month-end performance per product based on month-to-date pace.
///
/// Math: `projected = current * (daysInMonth / daysElapsed)` for both
/// [TopProduct.amount] and [TopProduct.quantity].
class ProductProjectionCard extends StatelessWidget {
  const ProductProjectionCard({
    super.key,
    required this.products,
    this.maxItems = 5,
    DateTime? now,
  }) : _nowOverride = now;

  final List<TopProduct> products;
  final int maxItems;
  final DateTime? _nowOverride;

  @override
  Widget build(BuildContext context) {
    final dpi = DpiScale.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final now = _nowOverride ?? DateTime.now();

    final daysInMonth = DateTime(now.year, now.month + 1, 0).day;
    final daysElapsed = now.day;
    final scale = daysElapsed > 0 ? daysInMonth / daysElapsed : 1.0;

    if (products.isEmpty) return const SizedBox.shrink();

    // Build projected list, sorted by projected amount.
    final projected = products
        .map((p) => _ProjectedProduct(
              label: p.label,
              currentAmount: p.amount,
              currentQty: p.quantity,
              projectedAmount: p.amount * scale,
              projectedQty: p.quantity * scale,
            ))
        .toList()
      ..sort((a, b) => b.projectedAmount.compareTo(a.projectedAmount));

    final shown = projected.take(maxItems).toList();
    final maxProjected = shown.first.projectedAmount;

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
                  color: MangoThemeFactory.mango.withValues(alpha: isDark ? 0.2 : 0.12),
                  borderRadius: BorderRadius.circular(dpi.radius(10)),
                ),
                child: Icon(Icons.auto_graph_rounded, color: MangoThemeFactory.mango, size: dpi.icon(20)),
              ),
              SizedBox(width: dpi.space(10)),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Proyección por producto',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    Text(
                      'Top ${shown.length} al ritmo de este mes',
                      style: TextStyle(fontSize: dpi.font(11), color: MangoThemeFactory.mutedText(context)),
                    ),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: dpi.space(14)),
          for (var i = 0; i < shown.length; i++) ...[
            _ProjectionRow(
              rank: i + 1,
              data: shown[i],
              maxProjected: maxProjected,
            ),
            if (i < shown.length - 1) SizedBox(height: dpi.space(12)),
          ],
        ],
      ),
    );
  }
}

class _ProjectedProduct {
  const _ProjectedProduct({
    required this.label,
    required this.currentAmount,
    required this.currentQty,
    required this.projectedAmount,
    required this.projectedQty,
  });

  final String label;
  final double currentAmount;
  final double currentQty;
  final double projectedAmount;
  final double projectedQty;
}

class _ProjectionRow extends StatelessWidget {
  const _ProjectionRow({
    required this.rank,
    required this.data,
    required this.maxProjected,
  });

  final int rank;
  final _ProjectedProduct data;
  final double maxProjected;

  @override
  Widget build(BuildContext context) {
    final dpi = DpiScale.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final share = maxProjected == 0 ? 0.0 : (data.projectedAmount / maxProjected);

    final rankColor = rank == 1
        ? MangoThemeFactory.mango
        : rank == 2
            ? MangoThemeFactory.warning
            : rank == 3
                ? MangoThemeFactory.info
                : MangoThemeFactory.mutedText(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: dpi.scale(22),
              height: dpi.scale(22),
              decoration: BoxDecoration(
                color: rankColor.withValues(alpha: isDark ? 0.2 : 0.12),
                borderRadius: BorderRadius.circular(dpi.radius(6)),
              ),
              alignment: Alignment.center,
              child: Text(
                '$rank',
                style: TextStyle(fontSize: dpi.font(10), fontWeight: FontWeight.w800, color: rankColor),
              ),
            ),
            SizedBox(width: dpi.space(8)),
            Expanded(
              child: Text(
                data.label,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            SizedBox(width: dpi.space(6)),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                MangoFormatters.currency(data.projectedAmount),
                style: TextStyle(
                  fontSize: dpi.font(13),
                  fontWeight: FontWeight.w800,
                  color: MangoThemeFactory.mango,
                ),
              ),
            ),
          ],
        ),
        SizedBox(height: dpi.space(4)),
        Padding(
          padding: EdgeInsets.only(left: dpi.space(30)),
          child: Text(
            '${MangoFormatters.number(data.projectedQty.round())} uds proyectadas · ${MangoFormatters.number(data.currentQty.round())} vendidas hoy',
            style: TextStyle(fontSize: dpi.font(11), color: MangoThemeFactory.mutedText(context)),
          ),
        ),
        SizedBox(height: dpi.space(6)),
        Padding(
          padding: EdgeInsets.only(left: dpi.space(30)),
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
                      colors: [MangoThemeFactory.mango, MangoThemeFactory.mango.withValues(alpha: 0.7)],
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
  }
}
