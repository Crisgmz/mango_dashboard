import 'package:flutter/material.dart';

import '../../../core/formatters/mango_formatters.dart';
import '../../../core/responsive/dpi_scale.dart';
import '../../../domain/inventory/inventory_models.dart';
import '../../theme/theme_data_factory.dart';

/// Fila de artículo de la Vista de stock (PRD 6.2 B.1):
/// borde izquierdo 4px = semáforo de cobertura vs. punto de reorden,
/// "en mano" arriba a la derecha, y los cuatro mini-datos DISPON. /
/// EN ORDEN / COSTO PROM. / MARGEN. El semáforo es el único adorno
/// cromático; el resto es tipografía.
class StockRow extends StatelessWidget {
  const StockRow({
    super.key,
    required this.item,
    required this.onOrder,
    required this.committed,
    this.price,
    this.onTap,
  });

  final InventoryItemSnapshot item;

  /// Unidades en POs enviadas sin recibir.
  final double onOrder;

  /// Unidades comprometidas en órdenes abiertas del POS.
  final double committed;

  /// Precio de venta del producto vinculado (null si el insumo no vende
  /// directo → sin margen).
  final double? price;

  final VoidCallback? onTap;

  /// Disponible = en mano − comprometido, nunca negativo en display.
  double get available =>
      (item.totalQuantity - committed).clamp(double.negativeInfinity, double.infinity);

  double? get marginPct {
    final p = price;
    final c = item.cost;
    if (p == null || p <= 0 || c == null) return null;
    return (p - c) / p * 100;
  }

  /// Semáforo de cobertura: verde ≥ 1.5× reorden · ámbar 1–1.5× · rojo por
  /// debajo. Sin punto de reorden configurado → neutro.
  Color _coverageColor(BuildContext context) {
    final min = item.minStock;
    if (min <= 0) return MangoThemeFactory.borderColor(context);
    final qty = item.totalQuantity;
    if (qty >= min * 1.5) return MangoThemeFactory.success;
    if (qty >= min) return MangoThemeFactory.warning;
    return MangoThemeFactory.danger;
  }

  Color _marginColor(BuildContext context, double pct) {
    if (pct >= 30) return MangoThemeFactory.success;
    if (pct >= 15) return MangoThemeFactory.warning;
    return MangoThemeFactory.danger;
  }

  @override
  Widget build(BuildContext context) {
    final dpi = DpiScale.of(context);
    final coverage = _coverageColor(context);
    final margin = marginPct;
    final belowMin = item.minStock > 0 && item.totalQuantity < item.minStock;

    return Container(
      margin: EdgeInsets.only(bottom: dpi.space(8)),
      decoration: BoxDecoration(
        color: MangoThemeFactory.cardColor(context),
        borderRadius: BorderRadius.circular(dpi.radius(14)),
        border: Border.all(color: MangoThemeFactory.borderColor(context)),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(dpi.radius(14)),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Borde-semáforo de cobertura (4px).
                Container(
                  width: 4,
                  decoration: BoxDecoration(
                    color: coverage,
                    borderRadius: BorderRadius.horizontal(
                        left: Radius.circular(dpi.radius(14))),
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(dpi.space(12), dpi.space(10),
                        dpi.space(12), dpi.space(10)),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    item.name,
                                    style: TextStyle(
                                      fontSize: dpi.font(13.5),
                                      fontWeight: FontWeight.w700,
                                      color:
                                          MangoThemeFactory.textColor(context),
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  SizedBox(height: dpi.space(1)),
                                  Text(
                                    [
                                      item.unit,
                                      if (item.sku != null &&
                                          item.sku!.isNotEmpty)
                                        item.sku!,
                                    ].join(' · '),
                                    style: TextStyle(
                                      fontSize: dpi.font(10.5),
                                      color:
                                          MangoThemeFactory.mutedText(context),
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                            SizedBox(width: dpi.space(8)),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  MangoFormatters.number(item.totalQuantity),
                                  style: TextStyle(
                                    fontSize: dpi.font(16),
                                    fontWeight: FontWeight.w800,
                                    color: belowMin
                                        ? MangoThemeFactory.danger
                                        : MangoThemeFactory.textColor(context),
                                  ),
                                ),
                                Text(
                                  'en mano',
                                  style: TextStyle(
                                    fontSize: dpi.font(9),
                                    color: MangoThemeFactory.mutedText(context),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                        SizedBox(height: dpi.space(8)),
                        Container(
                          padding: EdgeInsets.symmetric(
                              horizontal: dpi.space(10),
                              vertical: dpi.space(6)),
                          decoration: BoxDecoration(
                            color: MangoThemeFactory.altSurface(context),
                            borderRadius:
                                BorderRadius.circular(dpi.radius(10)),
                          ),
                          child: Row(
                            children: [
                              _MiniStat(
                                label: 'DISPON.',
                                value: MangoFormatters.number(available),
                                color: available <= 0
                                    ? MangoThemeFactory.danger
                                    : null,
                              ),
                              _MiniStat(
                                label: 'EN ORDEN',
                                value: onOrder > 0
                                    ? '+${MangoFormatters.number(onOrder)}'
                                    : '0',
                                color: onOrder > 0
                                    ? MangoThemeFactory.info
                                    : MangoThemeFactory.mutedText(context),
                              ),
                              _MiniStat(
                                label: 'COSTO PROM.',
                                value: item.cost != null
                                    ? MangoFormatters.currency(item.cost!)
                                    : '—',
                              ),
                              _MiniStat(
                                label: 'MARGEN',
                                value: margin != null
                                    ? '${margin.toStringAsFixed(0)}%'
                                    : '—',
                                color: margin != null
                                    ? _marginColor(context, margin)
                                    : MangoThemeFactory.mutedText(context),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({required this.label, required this.value, this.color});

  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final dpi = DpiScale.of(context);
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: dpi.font(8),
              fontWeight: FontWeight.w800,
              letterSpacing: 0.3,
              color: MangoThemeFactory.mutedText(context),
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          SizedBox(height: dpi.space(1)),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: TextStyle(
                fontSize: dpi.font(12),
                fontWeight: FontWeight.w800,
                color: color ?? MangoThemeFactory.textColor(context),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
