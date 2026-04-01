import 'package:flutter/material.dart';

import '../../../core/responsive/dpi_scale.dart';
import '../../../domain/dashboard/dashboard_models.dart';
import '../../theme/theme_data_factory.dart';

class DashboardTopProducts extends StatelessWidget {
  const DashboardTopProducts({super.key, required this.products});

  final List<TopProduct> products;

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
          Row(
            children: [
              Container(
                width: dpi.scale(36),
                height: dpi.scale(36),
                decoration: BoxDecoration(
                  color: MangoThemeFactory.mango.withValues(alpha: isDark ? 0.2 : 0.12),
                  borderRadius: BorderRadius.circular(dpi.radius(10)),
                ),
                child: Icon(Icons.local_fire_department_rounded, color: MangoThemeFactory.mango, size: dpi.icon(20)),
              ),
              SizedBox(width: dpi.space(10)),
              Expanded(
                child: Text(
                  'Productos más vendidos',
                  style: Theme.of(context).textTheme.titleMedium,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          SizedBox(height: dpi.space(14)),
          if (products.isEmpty)
            Padding(
              padding: EdgeInsets.symmetric(vertical: dpi.space(20)),
              child: Center(
                child: Text(
                  'Sin productos vendidos aún',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            )
          else
            ...List.generate(products.length, (index) {
              final product = products[index];
              return _ProductRow(product: product, rank: index + 1, isLast: index == products.length - 1);
            }),
        ],
      ),
    );
  }
}

class _ProductRow extends StatelessWidget {
  const _ProductRow({required this.product, required this.rank, required this.isLast});

  final TopProduct product;
  final int rank;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final dpi = DpiScale.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final rankColors = [
      MangoThemeFactory.mango,
      MangoThemeFactory.warning,
      MangoThemeFactory.info,
      MangoThemeFactory.mutedText(context),
      MangoThemeFactory.mutedText(context),
    ];
    final color = rank <= rankColors.length ? rankColors[rank - 1] : MangoThemeFactory.mutedText(context);

    return Container(
      padding: EdgeInsets.symmetric(vertical: dpi.space(10)),
      decoration: BoxDecoration(
        border: isLast ? null : Border(bottom: BorderSide(color: MangoThemeFactory.borderColor(context))),
      ),
      child: Row(
        children: [
          Container(
            width: dpi.scale(30),
            height: dpi.scale(30),
            decoration: BoxDecoration(
              color: color.withValues(alpha: isDark ? 0.2 : 0.12),
              borderRadius: BorderRadius.circular(dpi.radius(8)),
            ),
            child: Center(
              child: Text(
                '#$rank',
                style: TextStyle(fontSize: dpi.font(11), fontWeight: FontWeight.w800, color: color),
              ),
            ),
          ),
          SizedBox(width: dpi.space(10)),
          Container(
            width: dpi.scale(36),
            height: dpi.scale(36),
            decoration: BoxDecoration(
              color: MangoThemeFactory.altSurface(context),
              borderRadius: BorderRadius.circular(dpi.radius(10)),
            ),
            child: Icon(Icons.fastfood_rounded, size: dpi.icon(18), color: MangoThemeFactory.mutedText(context)),
          ),
          SizedBox(width: dpi.space(10)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  product.label,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(fontSize: dpi.font(13)),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                SizedBox(height: dpi.space(2)),
                Text(
                  '${product.quantity.toStringAsFixed(0)} vendidos',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(fontSize: dpi.font(11)),
                ),
              ],
            ),
          ),
          SizedBox(width: dpi.space(6)),
          Flexible(
            flex: 0,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                'RD\$ ${product.amount.toStringAsFixed(2)}',
                style: TextStyle(
                  fontSize: dpi.font(13),
                  fontWeight: FontWeight.w700,
                  color: MangoThemeFactory.textColor(context),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
