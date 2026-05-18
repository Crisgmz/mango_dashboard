import 'package:flutter/material.dart';

import '../../../core/responsive/dpi_scale.dart';
import '../../theme/theme_data_factory.dart';

/// Date range presets used by the in-screen filter bar on detail views
/// (modifiers, customers, etc.). Mirrors a subset of the dashboard's
/// `SalesDateFilter` and adds a sticky "initial" entry for the period
/// inherited from the dashboard.
enum DetailPeriod { initial, today, yesterday, week, month, custom }

/// Resolves the [DateTimeRange] for a given preset, anchored to `now`.
/// `initial` returns null because that range comes from the caller.
DateTimeRange? rangeForDetailPeriod(DetailPeriod period, DateTime now) {
  final today = DateTime(now.year, now.month, now.day);
  switch (period) {
    case DetailPeriod.today:
      return DateTimeRange(start: today, end: today.add(const Duration(days: 1)));
    case DetailPeriod.yesterday:
      final start = today.subtract(const Duration(days: 1));
      return DateTimeRange(start: start, end: today);
    case DetailPeriod.week:
      return DateTimeRange(
        start: today.subtract(const Duration(days: 7)),
        end: today.add(const Duration(days: 1)),
      );
    case DetailPeriod.month:
      return DateTimeRange(
        start: DateTime(now.year, now.month, 1),
        end: DateTime(now.year, now.month + 1, 1),
      );
    case DetailPeriod.initial:
    case DetailPeriod.custom:
      return null;
  }
}

String labelForDetailPeriod(DetailPeriod period, {DateTimeRange? customRange, String? initialLabel}) {
  switch (period) {
    case DetailPeriod.initial:
      return initialLabel ?? 'Periodo';
    case DetailPeriod.today:
      return 'Hoy';
    case DetailPeriod.yesterday:
      return 'Ayer';
    case DetailPeriod.week:
      return '7 días';
    case DetailPeriod.month:
      return 'Mes';
    case DetailPeriod.custom:
      final r = customRange;
      if (r == null) return 'Personalizado';
      return '${r.start.day}/${r.start.month} - ${r.end.day}/${r.end.month}';
  }
}

/// Horizontal chip row used to pick a date preset on detail screens.
/// Receives the already-computed [selected] enum and notifies the parent
/// via [onSelected]. Custom range picking is delegated to the caller via
/// [onPickCustom] so the parent can run an async picker and update state.
class PeriodFilterBar extends StatelessWidget {
  const PeriodFilterBar({
    super.key,
    required this.selected,
    required this.onSelected,
    required this.onPickCustom,
    this.accent,
    this.initialLabel,
    this.customRange,
  });

  final DetailPeriod selected;
  final ValueChanged<DetailPeriod> onSelected;
  final Future<void> Function() onPickCustom;
  final Color? accent;
  final String? initialLabel;
  final DateTimeRange? customRange;

  @override
  Widget build(BuildContext context) {
    final dpi = DpiScale.of(context);
    final color = accent ?? MangoThemeFactory.info;
    return SizedBox(
      height: dpi.scale(34),
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.symmetric(horizontal: dpi.space(16)),
        children: [
          if (initialLabel != null) ...[
            _Chip(
              label: initialLabel!,
              selected: selected == DetailPeriod.initial,
              accent: color,
              onTap: () => onSelected(DetailPeriod.initial),
            ),
            SizedBox(width: dpi.space(6)),
          ],
          _Chip(
            label: 'Hoy',
            selected: selected == DetailPeriod.today,
            accent: color,
            onTap: () => onSelected(DetailPeriod.today),
          ),
          SizedBox(width: dpi.space(6)),
          _Chip(
            label: 'Ayer',
            selected: selected == DetailPeriod.yesterday,
            accent: color,
            onTap: () => onSelected(DetailPeriod.yesterday),
          ),
          SizedBox(width: dpi.space(6)),
          _Chip(
            label: '7 días',
            selected: selected == DetailPeriod.week,
            accent: color,
            onTap: () => onSelected(DetailPeriod.week),
          ),
          SizedBox(width: dpi.space(6)),
          _Chip(
            label: 'Mes',
            selected: selected == DetailPeriod.month,
            accent: color,
            onTap: () => onSelected(DetailPeriod.month),
          ),
          SizedBox(width: dpi.space(6)),
          _Chip(
            label: labelForDetailPeriod(DetailPeriod.custom, customRange: customRange),
            selected: selected == DetailPeriod.custom,
            accent: color,
            icon: Icons.calendar_today_rounded,
            onTap: onPickCustom,
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.selected,
    required this.accent,
    required this.onTap,
    this.icon,
  });

  final String label;
  final bool selected;
  final Color accent;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final dpi = DpiScale.of(context);
    return ChoiceChip(
      avatar: icon == null
          ? null
          : Icon(icon, size: dpi.icon(14), color: selected ? accent : MangoThemeFactory.mutedText(context)),
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
      showCheckmark: false,
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      selectedColor: accent.withValues(alpha: 0.2),
      labelStyle: TextStyle(
        color: selected ? accent : null,
        fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
        fontSize: dpi.font(12),
      ),
    );
  }
}
