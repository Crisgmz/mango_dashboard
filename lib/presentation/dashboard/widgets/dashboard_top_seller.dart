import 'package:flutter/material.dart';

import '../../../core/responsive/dpi_scale.dart';
import '../../../domain/dashboard/dashboard_models.dart';
import '../../theme/theme_data_factory.dart';

class DashboardTopSeller extends StatelessWidget {
  const DashboardTopSeller({super.key, required this.seller});

  final TopSeller seller;

  @override
  Widget build(BuildContext context) {
    final dpi = DpiScale.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final initial = seller.name.isNotEmpty ? seller.name[0].toUpperCase() : '?';

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
                  color: MangoThemeFactory.success.withValues(alpha: isDark ? 0.2 : 0.12),
                  borderRadius: BorderRadius.circular(dpi.radius(10)),
                ),
                child: Icon(Icons.emoji_events_rounded, color: MangoThemeFactory.success, size: dpi.icon(20)),
              ),
              SizedBox(width: dpi.space(10)),
              Expanded(
                child: Text(
                  'Mejor vendedor del día',
                  style: Theme.of(context).textTheme.titleMedium,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          SizedBox(height: dpi.space(18)),
          Row(
            children: [
              Container(
                width: dpi.scale(50),
                height: dpi.scale(50),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [MangoThemeFactory.mango, MangoThemeFactory.mangoDeep],
                  ),
                  borderRadius: BorderRadius.circular(dpi.radius(14)),
                ),
                child: Center(
                  child: Text(
                    initial,
                    style: TextStyle(
                      fontSize: dpi.font(22),
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
              SizedBox(width: dpi.space(14)),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            seller.name,
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        SizedBox(width: dpi.space(6)),
                        Container(
                          padding: EdgeInsets.symmetric(horizontal: dpi.space(7), vertical: dpi.space(3)),
                          decoration: BoxDecoration(
                            color: MangoThemeFactory.mango.withValues(alpha: isDark ? 0.2 : 0.12),
                            borderRadius: BorderRadius.circular(dpi.radius(6)),
                          ),
                          child: Text(
                            'Top Seller',
                            style: TextStyle(
                              fontSize: dpi.font(9),
                              fontWeight: FontWeight.w700,
                              color: MangoThemeFactory.mango,
                            ),
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: dpi.space(4)),
                    Text(
                      '${seller.orderCount} órdenes atendidas',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: dpi.space(14)),
          Container(
            width: double.infinity,
            padding: EdgeInsets.symmetric(vertical: dpi.space(10), horizontal: dpi.space(14)),
            decoration: BoxDecoration(
              color: MangoThemeFactory.success.withValues(alpha: isDark ? 0.15 : 0.08),
              borderRadius: BorderRadius.circular(dpi.radius(12)),
            ),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.attach_money_rounded, color: MangoThemeFactory.success, size: dpi.icon(20)),
                  SizedBox(width: dpi.space(4)),
                  Text(
                    'RD\$ ${seller.totalSales.toStringAsFixed(2)}',
                    style: TextStyle(
                      fontSize: dpi.font(18),
                      fontWeight: FontWeight.w800,
                      color: MangoThemeFactory.success,
                    ),
                  ),
                  SizedBox(width: dpi.space(8)),
                  Text(
                    'en ventas hoy',
                    style: TextStyle(
                      fontSize: dpi.font(12),
                      color: MangoThemeFactory.success.withValues(alpha: 0.8),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
