import 'package:flutter/material.dart';

import '../../../core/responsive/dpi_scale.dart';
import '../../../domain/accounting/dgii_reports.dart';
import '../../theme/theme_data_factory.dart';

/// Selector de mes de los formatos de la DGII. No reusa `PeriodFilterBar`
/// porque estos archivos son mensuales por norma: el período siempre es un mes
/// completo, nunca "últimos 7 días" ni un rango libre.
class DgiiPeriodBar extends StatelessWidget {
  const DgiiPeriodBar({
    super.key,
    required this.period,
    required this.onChanged,
  });

  final DgiiPeriod period;
  final ValueChanged<DgiiPeriod> onChanged;

  @override
  Widget build(BuildContext context) {
    final dpi = DpiScale.of(context);
    final thisMonth = DgiiPeriod.of(DateTime.now());
    // El mes en curso todavía no cerró: se deja ver (para revisar cómo va),
    // pero no se puede avanzar más allá.
    final canGoForward = !period.next.isAfter(thisMonth);

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: dpi.space(16)),
      child: Container(
        padding: EdgeInsets.symmetric(
            horizontal: dpi.space(6), vertical: dpi.space(6)),
        decoration: BoxDecoration(
          color: MangoThemeFactory.cardColor(context),
          borderRadius: BorderRadius.circular(dpi.radius(14)),
          border: Border.all(color: MangoThemeFactory.borderColor(context)),
        ),
        child: Row(
          children: [
            _Arrow(
              icon: Icons.chevron_left_rounded,
              tooltip: 'Mes anterior',
              onTap: () => onChanged(period.previous),
            ),
            Expanded(
              child: InkWell(
                borderRadius: BorderRadius.circular(dpi.radius(10)),
                onTap: () => _pickMonth(context, thisMonth),
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: dpi.space(8)),
                  child: Column(
                    children: [
                      Text(
                        period.label,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: dpi.font(14.5),
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      SizedBox(height: dpi.space(1)),
                      Text(
                        period == thisMonth
                            ? 'Mes en curso · aún no cierra'
                            : 'Período ${period.code}',
                        style: TextStyle(
                          fontSize: dpi.font(10.5),
                          color: period == thisMonth
                              ? MangoThemeFactory.warning
                              : MangoThemeFactory.mutedText(context),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            _Arrow(
              icon: Icons.chevron_right_rounded,
              tooltip: 'Mes siguiente',
              onTap: canGoForward ? () => onChanged(period.next) : null,
            ),
          ],
        ),
      ),
    );
  }

  /// Hoja de selección rápida: los últimos 24 meses, el más reciente arriba.
  Future<void> _pickMonth(BuildContext context, DgiiPeriod thisMonth) async {
    final dpi = DpiScale.of(context);
    final months = <DgiiPeriod>[];
    var cursor = thisMonth;
    for (var i = 0; i < 24; i++) {
      months.add(cursor);
      cursor = cursor.previous;
    }

    final picked = await showModalBottomSheet<DgiiPeriod>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => Container(
        height: MediaQuery.of(sheetContext).size.height * 0.6,
        decoration: BoxDecoration(
          color: Theme.of(sheetContext).scaffoldBackgroundColor,
          borderRadius: BorderRadius.vertical(
              top: Radius.circular(dpi.radius(24))),
        ),
        child: Column(
          children: [
            Padding(
              padding: EdgeInsets.symmetric(vertical: dpi.space(10)),
              child: Container(
                width: dpi.scale(40),
                height: dpi.scale(4),
                decoration: BoxDecoration(
                  color: MangoThemeFactory.borderColor(sheetContext),
                  borderRadius: BorderRadius.circular(dpi.radius(2)),
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(
                  dpi.space(16), 0, dpi.space(16), dpi.space(10)),
              child: Row(
                children: [
                  Text(
                    'PERÍODO A DECLARAR',
                    style: TextStyle(
                      fontSize: dpi.font(11),
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.6,
                      color: MangoThemeFactory.mutedText(sheetContext),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                padding: EdgeInsets.fromLTRB(dpi.space(16), 0, dpi.space(16),
                    dpi.space(16) + MediaQuery.of(sheetContext).padding.bottom),
                itemCount: months.length,
                itemBuilder: (_, i) {
                  final month = months[i];
                  final selected = month == period;
                  return Container(
                    margin: EdgeInsets.only(bottom: dpi.space(8)),
                    decoration: BoxDecoration(
                      color: MangoThemeFactory.cardColor(sheetContext),
                      borderRadius: BorderRadius.circular(dpi.radius(14)),
                      border: Border.all(
                        color: selected
                            ? MangoThemeFactory.mango
                            : MangoThemeFactory.borderColor(sheetContext),
                      ),
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(dpi.radius(14)),
                        onTap: () => Navigator.of(sheetContext).pop(month),
                        child: Padding(
                          padding: EdgeInsets.symmetric(
                              horizontal: dpi.space(14),
                              vertical: dpi.space(12)),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  month.label,
                                  style: TextStyle(
                                    fontSize: dpi.font(13.5),
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              Text(
                                month.code,
                                style: TextStyle(
                                  fontSize: dpi.font(11),
                                  color:
                                      MangoThemeFactory.mutedText(sheetContext),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              if (selected) ...[
                                SizedBox(width: dpi.space(8)),
                                Icon(Icons.check_circle_rounded,
                                    size: dpi.icon(18),
                                    color: MangoThemeFactory.mango),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
    if (picked != null && picked != period) onChanged(picked);
  }
}

class _Arrow extends StatelessWidget {
  const _Arrow({required this.icon, required this.tooltip, this.onTap});

  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final dpi = DpiScale.of(context);
    return IconButton(
      tooltip: tooltip,
      onPressed: onTap,
      icon: Icon(icon, size: dpi.icon(22)),
      color: onTap == null
          ? MangoThemeFactory.mutedText(context).withValues(alpha: 0.4)
          : MangoThemeFactory.textColor(context),
    );
  }
}
