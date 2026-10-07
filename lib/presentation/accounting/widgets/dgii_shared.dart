import 'package:flutter/material.dart';

import '../../../core/responsive/dpi_scale.dart';
import '../../../domain/accounting/dgii_catalogs.dart';
import '../../theme/theme_data_factory.dart';

/// Piezas compartidas por las tres pantallas de formatos (606/607/608): la
/// cabecera con los totales del período, el header de sección, la fila-card y
/// el selector de códigos de la DGII.

/// Cabecera naranja con el período y los totales que se van a declarar. Es la
/// única card con gradiente de estas pantallas — el resto son cards blandas.
class DgiiSummaryHeader extends StatelessWidget {
  const DgiiSummaryHeader({
    super.key,
    required this.formatCode,
    required this.periodLabel,
    required this.recordCount,
    required this.figures,
    required this.accent,
    this.warning,
  });

  final String formatCode;
  final String periodLabel;
  final int recordCount;

  /// Pares `etiqueta → valor ya formateado` que se pintan debajo del conteo.
  final List<({String label, String value})> figures;

  final Color accent;

  /// Aviso que bloquea o condiciona el envío (por ejemplo, falta el RNC).
  final String? warning;

  @override
  Widget build(BuildContext context) {
    final dpi = DpiScale.of(context);
    return Container(
      padding: EdgeInsets.all(dpi.space(18)),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [accent, accent.withValues(alpha: 0.78)],
        ),
        borderRadius: BorderRadius.circular(dpi.radius(20)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'FORMATO $formatCode',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.85),
              fontSize: dpi.font(11),
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
            ),
          ),
          SizedBox(height: dpi.space(4)),
          Text(
            periodLabel,
            style: TextStyle(
              color: Colors.white,
              fontSize: dpi.font(24),
              fontWeight: FontWeight.w800,
            ),
          ),
          SizedBox(height: dpi.space(2)),
          Text(
            recordCount == 1
                ? '1 registro a declarar'
                : '$recordCount registros a declarar',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.9),
              fontSize: dpi.font(12.5),
              fontWeight: FontWeight.w600,
            ),
          ),
          if (figures.isNotEmpty) ...[
            SizedBox(height: dpi.space(14)),
            Wrap(
              spacing: dpi.space(20),
              runSpacing: dpi.space(10),
              children: [
                for (final f in figures)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        f.label.toUpperCase(),
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.8),
                          fontSize: dpi.font(10),
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.5,
                        ),
                      ),
                      SizedBox(height: dpi.space(2)),
                      Text(
                        f.value,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: dpi.font(15),
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ],
          if (warning != null) ...[
            SizedBox(height: dpi.space(14)),
            Container(
              width: double.infinity,
              padding: EdgeInsets.all(dpi.space(10)),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(dpi.radius(10)),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline_rounded,
                      color: Colors.white, size: dpi.icon(16)),
                  SizedBox(width: dpi.space(8)),
                  Expanded(
                    child: Text(
                      warning!,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: dpi.font(11.5),
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Header de sección: MAYÚSCULAS pequeñas con contador y acción opcional.
class DgiiSectionHeader extends StatelessWidget {
  const DgiiSectionHeader({
    super.key,
    required this.label,
    this.count,
    this.trailing,
  });

  final String label;
  final int? count;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final dpi = DpiScale.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: dpi.space(8)),
      child: Row(
        children: [
          Expanded(
            child: Text(
              count == null ? label : '$label ($count)',
              style: TextStyle(
                fontSize: dpi.font(11.5),
                fontWeight: FontWeight.w700,
                letterSpacing: 0.6,
                color: MangoThemeFactory.mutedText(context),
              ),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// Fila del listado como card blanda: avatar de inicial, título + subtítulo y
/// un bloque a la derecha (monto, chip de clasificación…).
class DgiiRowCard extends StatelessWidget {
  const DgiiRowCard({
    super.key,
    required this.leading,
    required this.title,
    required this.subtitle,
    this.detail,
    this.trailing,
    this.accent,
    this.onTap,
    this.flagged = false,
  });

  /// Texto corto del avatar (una o dos letras, o el tipo de NCF).
  final String leading;

  final String title;
  final String subtitle;

  /// Tercera línea opcional para el desglose de montos.
  final String? detail;

  final Widget? trailing;
  final Color? accent;
  final VoidCallback? onTap;

  /// Marca la fila con borde de atención: le falta algo para poder declararla.
  final bool flagged;

  @override
  Widget build(BuildContext context) {
    final dpi = DpiScale.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color = accent ?? MangoThemeFactory.mango;
    final card = Container(
      padding: EdgeInsets.all(dpi.space(12)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: dpi.scale(36),
            height: dpi.scale(36),
            decoration: BoxDecoration(
              color: color.withValues(alpha: isDark ? 0.2 : 0.1),
              borderRadius: BorderRadius.circular(dpi.radius(10)),
            ),
            alignment: Alignment.center,
            child: Text(
              leading,
              style: TextStyle(
                color: color,
                fontSize: dpi.font(leading.length > 2 ? 10 : 13),
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          SizedBox(width: dpi.space(12)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: dpi.font(13.5),
                    fontWeight: FontWeight.w700,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                SizedBox(height: dpi.space(2)),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: dpi.font(11),
                    color: MangoThemeFactory.mutedText(context),
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                if (detail != null) ...[
                  SizedBox(height: dpi.space(4)),
                  Text(
                    detail!,
                    style: TextStyle(
                      fontSize: dpi.font(11),
                      color: MangoThemeFactory.mutedText(context),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (trailing != null) ...[
            SizedBox(width: dpi.space(10)),
            trailing!,
          ],
        ],
      ),
    );

    return Container(
      margin: EdgeInsets.only(bottom: dpi.space(8)),
      decoration: BoxDecoration(
        color: MangoThemeFactory.cardColor(context),
        borderRadius: BorderRadius.circular(dpi.radius(14)),
        border: Border.all(
          color: flagged
              ? MangoThemeFactory.warning
              : MangoThemeFactory.borderColor(context),
        ),
      ),
      child: onTap == null
          ? card
          : Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(dpi.radius(14)),
                onTap: onTap,
                child: card,
              ),
            ),
    );
  }
}

/// Chip que muestra el código de la DGII elegido para una fila y abre el
/// selector al tocarlo.
class DgiiCodeChip extends StatelessWidget {
  const DgiiCodeChip({
    super.key,
    required this.code,
    required this.catalog,
    required this.onPick,
  });

  final String code;
  final List<DgiiCode> catalog;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    final dpi = DpiScale.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(dpi.radius(10)),
        onTap: () async {
          final picked = await showDgiiCodePicker(
            context: context,
            catalog: catalog,
            selected: code,
          );
          if (picked != null) onPick(picked);
        },
        child: Container(
          padding: EdgeInsets.symmetric(
              horizontal: dpi.space(9), vertical: dpi.space(6)),
          decoration: BoxDecoration(
            color: MangoThemeFactory.altSurface(context),
            borderRadius: BorderRadius.circular(dpi.radius(10)),
            border: Border.all(color: MangoThemeFactory.borderColor(context)),
          ),
          child: Row(
            children: [
              Text(
                code,
                style: TextStyle(
                  fontSize: dpi.font(12),
                  fontWeight: FontWeight.w800,
                ),
              ),
              SizedBox(width: dpi.space(4)),
              Icon(Icons.expand_more_rounded,
                  size: dpi.icon(14),
                  color: MangoThemeFactory.mutedText(context)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Selector de un código de la DGII, con la anatomía de `showSoftItemPicker`:
/// fondo scaffold, esquinas 24, asa de arrastre y resultados como cards
/// blandas. Sin búsqueda porque los catálogos tienen 11 entradas como máximo.
Future<String?> showDgiiCodePicker({
  required BuildContext context,
  required List<DgiiCode> catalog,
  required String selected,
  String title = 'CLASIFICACIÓN DE LA DGII',
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) {
      final dpi = DpiScale.of(sheetContext);
      return Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(sheetContext).size.height * 0.75,
        ),
        decoration: BoxDecoration(
          color: Theme.of(sheetContext).scaffoldBackgroundColor,
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(dpi.radius(24))),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
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
                    title,
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
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                padding: EdgeInsets.fromLTRB(dpi.space(16), 0, dpi.space(16),
                    dpi.space(16) + MediaQuery.of(sheetContext).padding.bottom),
                itemCount: catalog.length,
                itemBuilder: (_, i) {
                  final entry = catalog[i];
                  final isSelected = entry.code == selected;
                  return Container(
                    margin: EdgeInsets.only(bottom: dpi.space(8)),
                    decoration: BoxDecoration(
                      color: MangoThemeFactory.cardColor(sheetContext),
                      borderRadius: BorderRadius.circular(dpi.radius(14)),
                      border: Border.all(
                        color: isSelected
                            ? MangoThemeFactory.mango
                            : MangoThemeFactory.borderColor(sheetContext),
                      ),
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(dpi.radius(14)),
                        onTap: () => Navigator.of(sheetContext).pop(entry.code),
                        child: Padding(
                          padding: EdgeInsets.symmetric(
                              horizontal: dpi.space(14),
                              vertical: dpi.space(12)),
                          child: Row(
                            children: [
                              Container(
                                width: dpi.scale(34),
                                height: dpi.scale(34),
                                decoration: BoxDecoration(
                                  color: MangoThemeFactory.mango
                                      .withValues(alpha: 0.1),
                                  borderRadius:
                                      BorderRadius.circular(dpi.radius(10)),
                                ),
                                alignment: Alignment.center,
                                child: Text(
                                  entry.code,
                                  style: TextStyle(
                                    color: MangoThemeFactory.mango,
                                    fontSize: dpi.font(12),
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                              SizedBox(width: dpi.space(12)),
                              Expanded(
                                child: Text(
                                  entry.label,
                                  style: TextStyle(
                                    fontSize: dpi.font(13),
                                    fontWeight: FontWeight.w600,
                                    height: 1.3,
                                  ),
                                ),
                              ),
                              if (isSelected) ...[
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
      );
    },
  );
}

/// Estado vacío: ícono apagado, título corto y una línea que enseña qué hacer.
class DgiiEmptyState extends StatelessWidget {
  const DgiiEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.isError = false,
  });

  final IconData icon;
  final String title;
  final String message;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final dpi = DpiScale.of(context);
    final color = isError
        ? MangoThemeFactory.danger
        : MangoThemeFactory.mutedText(context);
    return Center(
      child: Padding(
        padding: EdgeInsets.all(dpi.space(28)),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: dpi.icon(42), color: color),
            SizedBox(height: dpi.space(12)),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: dpi.font(15),
                fontWeight: FontWeight.w700,
                color: isError ? MangoThemeFactory.danger : null,
              ),
            ),
            SizedBox(height: dpi.space(6)),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: dpi.font(12.5),
                color: MangoThemeFactory.mutedText(context),
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
