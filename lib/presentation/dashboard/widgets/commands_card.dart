import 'package:flutter/material.dart';

import '../../../core/responsive/dpi_scale.dart';
import '../../theme/theme_data_factory.dart';

/// Entry-point card for the comandas timeline. Shows the count and total so
/// the user knows there's something inside; tapping opens the full view.
class CommandsCard extends StatelessWidget {
  const CommandsCard({
    super.key,
    required this.ticketCount,
    required this.onTap,
  });

  final int ticketCount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final dpi = DpiScale.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(dpi.radius(18)),
      child: Container(
        padding: EdgeInsets.all(dpi.space(16)),
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
        child: Row(
          children: [
            Container(
              width: dpi.scale(40),
              height: dpi.scale(40),
              decoration: BoxDecoration(
                color: MangoThemeFactory.mango.withValues(alpha: isDark ? 0.2 : 0.12),
                borderRadius: BorderRadius.circular(dpi.radius(10)),
              ),
              child: Icon(Icons.receipt_long_rounded, color: MangoThemeFactory.mango, size: dpi.icon(22)),
            ),
            SizedBox(width: dpi.space(12)),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Comandas del periodo',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  SizedBox(height: dpi.space(2)),
                  Text(
                    ticketCount == 0
                        ? 'No hay comandas registradas'
                        : '$ticketCount ${ticketCount == 1 ? 'comanda' : 'comandas'} · ver una por una con sus productos',
                    style: TextStyle(fontSize: dpi.font(11), color: MangoThemeFactory.mutedText(context)),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: MangoThemeFactory.mutedText(context)),
          ],
        ),
      ),
    );
  }
}
