import 'package:flutter/material.dart';

import '../../../core/responsive/dpi_scale.dart';
import '../../../domain/billing/billing_enums.dart';
import '../../theme/theme_data_factory.dart';

/// Contenedor de tarjeta con el mismo estilo que las cards del dashboard.
class BillingCard extends StatelessWidget {
  const BillingCard({super.key, required this.child, this.padding});

  final Widget child;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final dpi = DpiScale.of(context);
    return Container(
      width: double.infinity,
      padding: padding ?? EdgeInsets.all(dpi.space(16)),
      decoration: BoxDecoration(
        color: MangoThemeFactory.cardColor(context),
        borderRadius: BorderRadius.circular(dpi.radius(16)),
        border: Border.all(color: MangoThemeFactory.borderColor(context)),
      ),
      child: child,
    );
  }
}

/// Ícono dentro de un cuadro con fondo tenue del color de acento.
class BillingIconBadge extends StatelessWidget {
  const BillingIconBadge({super.key, required this.icon, required this.color});

  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final dpi = DpiScale.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: dpi.scale(40),
      height: dpi.scale(40),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? 0.2 : 0.12),
        borderRadius: BorderRadius.circular(dpi.radius(10)),
      ),
      child: Icon(icon, color: color, size: dpi.icon(20)),
    );
  }
}

/// Etiqueta de estado (pill) coloreada.
class BillingStatusBadge extends StatelessWidget {
  const BillingStatusBadge({super.key, required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final dpi = DpiScale.of(context);
    return Container(
      padding: EdgeInsets.symmetric(horizontal: dpi.space(10), vertical: dpi.space(5)),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(dpi.radius(20)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: dpi.font(11),
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}

/// Aviso destacado (warning/danger/info) con ícono.
class BillingNotice extends StatelessWidget {
  const BillingNotice({
    super.key,
    required this.color,
    required this.icon,
    required this.message,
  });

  final Color color;
  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    final dpi = DpiScale.of(context);
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(dpi.space(12)),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(dpi.radius(12)),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: dpi.icon(18)),
          SizedBox(width: dpi.space(10)),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                fontSize: dpi.font(12.5),
                height: 1.35,
                color: MangoThemeFactory.textColor(context),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Color asociado a cada estado de cobro.
Color billingStatusColor(BillingStatus status) {
  switch (status) {
    case BillingStatus.trial:
      return MangoThemeFactory.info;
    case BillingStatus.active:
      return MangoThemeFactory.success;
    case BillingStatus.pastDue:
      return MangoThemeFactory.warning;
    case BillingStatus.suspended:
      return MangoThemeFactory.danger;
    case BillingStatus.cancelled:
      return const Color(0xFF9CA3AF);
    case BillingStatus.unknown:
      return const Color(0xFF9CA3AF);
  }
}
