import 'package:flutter/material.dart';

import '../../core/responsive/dpi_scale.dart';
import '../theme/theme_data_factory.dart';

/// Piezas de las pantallas de administración (categorías, salón): encabezado
/// de sección, estado vacío y fila "card blanda", según el design system.

/// `#RRGGBB` guardado en la base → Color (null si no es válido).
Color? parseHexColor(String? hex) {
  if (hex == null) return null;
  final clean = hex.replaceFirst('#', '');
  if (clean.length != 6) return null;
  final value = int.tryParse(clean, radix: 16);
  if (value == null) return null;
  return Color(0xFF000000 | value);
}

/// Label en MAYÚSCULAS con contador y una línea de ayuda opcional.
class SoftSectionHeader extends StatelessWidget {
  const SoftSectionHeader({
    super.key,
    required this.label,
    this.count,
    this.hint,
    this.trailing,
  });

  final String label;
  final int? count;
  final String? hint;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final dpi = DpiScale.of(context);
    final muted = MangoThemeFactory.mutedText(context);
    return Padding(
      padding: EdgeInsets.only(top: dpi.space(8), bottom: dpi.space(8)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  count == null ? label : '$label ($count)',
                  style: TextStyle(
                    fontSize: dpi.font(11.5),
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.6,
                    color: muted,
                  ),
                ),
                if (hint != null) ...[
                  SizedBox(height: dpi.space(2)),
                  Text(
                    hint!,
                    style: TextStyle(fontSize: dpi.font(11), color: muted),
                  ),
                ],
              ],
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// Estado vacío: ícono, título corto, una línea que enseña qué hacer y CTA.
class SoftEmptyState extends StatelessWidget {
  const SoftEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });

  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final dpi = DpiScale.of(context);
    final muted = MangoThemeFactory.mutedText(context);
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(dpi.space(24)),
      decoration: BoxDecoration(
        color: MangoThemeFactory.cardColor(context),
        borderRadius: BorderRadius.circular(dpi.radius(14)),
        border: Border.all(color: MangoThemeFactory.borderColor(context)),
      ),
      child: Column(
        children: [
          Icon(icon, size: dpi.icon(40), color: muted.withValues(alpha: 0.6)),
          SizedBox(height: dpi.space(10)),
          Text(
            title,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          SizedBox(height: dpi.space(4)),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: dpi.font(12.5), color: muted),
          ),
          if (action != null) ...[SizedBox(height: dpi.space(14)), action!],
        ],
      ),
    );
  }
}

/// Avatar de inicial (36x36, color al 10%, radio 10).
class SoftInitialAvatar extends StatelessWidget {
  const SoftInitialAvatar({
    super.key,
    required this.text,
    this.color,
    this.icon,
  });

  final String text;
  final Color? color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final dpi = DpiScale.of(context);
    final c = color ?? MangoThemeFactory.mango;
    return Container(
      width: dpi.scale(36),
      height: dpi.scale(36),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(dpi.radius(10)),
      ),
      child: icon != null
          ? Icon(icon, size: dpi.icon(18), color: c)
          : Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.clip,
              style: TextStyle(
                fontSize: dpi.font(text.length > 2 ? 10.5 : 14),
                fontWeight: FontWeight.w800,
                color: c,
              ),
            ),
    );
  }
}

/// Fila de lista como card blanda tocable: avatar, título w700 13.5,
/// subtítulo muted 11 y acción a la derecha.
class SoftRowCard extends StatelessWidget {
  const SoftRowCard({
    super.key,
    required this.leading,
    required this.title,
    this.subtitle,
    this.subtitleColor,
    this.trailing,
    this.onTap,
    this.muted = false,
  });

  final Widget leading;
  final String title;
  final String? subtitle;
  final Color? subtitleColor;
  final Widget? trailing;
  final VoidCallback? onTap;

  /// Atenuada (elementos desactivados).
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final dpi = DpiScale.of(context);
    final radius = BorderRadius.circular(dpi.radius(14));
    return Container(
      margin: EdgeInsets.only(bottom: dpi.space(8)),
      decoration: BoxDecoration(
        color: MangoThemeFactory.cardColor(context),
        borderRadius: radius,
        border: Border.all(color: MangoThemeFactory.borderColor(context)),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: radius,
          child: Opacity(
            opacity: muted ? 0.6 : 1,
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: dpi.space(12),
                vertical: dpi.space(10),
              ),
              child: Row(
                children: [
                  leading,
                  SizedBox(width: dpi.space(12)),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: dpi.font(13.5),
                            fontWeight: FontWeight.w700,
                            color: MangoThemeFactory.textColor(context),
                          ),
                        ),
                        if (subtitle != null) ...[
                          SizedBox(height: dpi.space(2)),
                          Text(
                            subtitle!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: dpi.font(11),
                              color:
                                  subtitleColor ??
                                  MangoThemeFactory.mutedText(context),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (trailing != null) ...[
                    SizedBox(width: dpi.space(8)),
                    trailing!,
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Píldora de estado (OCUPADA, OCULTA…).
class SoftStatusPill extends StatelessWidget {
  const SoftStatusPill({super.key, required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final dpi = DpiScale.of(context);
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: dpi.space(8),
        vertical: dpi.space(3),
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(dpi.radius(6)),
      ),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          fontSize: dpi.font(9),
          fontWeight: FontWeight.w800,
          letterSpacing: 0.4,
          color: color,
        ),
      ),
    );
  }
}
