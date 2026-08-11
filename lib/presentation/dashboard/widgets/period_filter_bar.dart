import 'package:flutter/material.dart';

import '../../../core/responsive/dpi_scale.dart';
import '../../../data/dashboard/business_day_service.dart';
import '../../theme/theme_data_factory.dart';

/// Date range presets used by the in-screen filter bar on detail views
/// (modifiers, customers, etc.). Mirrors a subset of the dashboard's
/// `SalesDateFilter` and adds a sticky "initial" entry for the period
/// inherited from the dashboard.
enum DetailPeriod { initial, today, yesterday, week, month, custom }

/// Resolves the [DateTimeRange] for a given preset, anchored to `now` and to
/// the business-day cutoff hour (default 5 AM): "Hoy" runs from today at the
/// cutoff to tomorrow at the cutoff, so a shift that crosses midnight still
/// counts as one operative day — same rule as the dashboard's Hoy/Ayer.
/// `initial` returns null because that range comes from the caller.
DateTimeRange? rangeForDetailPeriod(DetailPeriod period, DateTime now,
    {int? cutoffHour}) {
  final cutoff = cutoffHour ?? BusinessDayService.cachedCutoffHour;
  // Inicio del día OPERATIVO actual: hoy a la hora de corte, o ayer a esa hora
  // si todavía no hemos llegado al corte (ej. 2 AM con corte a las 5).
  var day = DateTime(now.year, now.month, now.day, cutoff);
  if (now.isBefore(day)) {
    day = DateTime(now.year, now.month, now.day - 1, cutoff);
  }
  DateTime shift(DateTime base, int days) =>
      DateTime(base.year, base.month, base.day + days, cutoff);
  switch (period) {
    case DetailPeriod.today:
      return DateTimeRange(start: day, end: shift(day, 1));
    case DetailPeriod.yesterday:
      return DateTimeRange(start: shift(day, -1), end: day);
    case DetailPeriod.week:
      return DateTimeRange(start: shift(day, -7), end: shift(day, 1));
    case DetailPeriod.month:
      return DateTimeRange(
        start: DateTime(day.year, day.month, 1, cutoff),
        end: DateTime(day.year, day.month + 1, 1, cutoff),
      );
    case DetailPeriod.initial:
    case DetailPeriod.custom:
      return null;
  }
}

/// Convierte los días elegidos en `showDateRangePicker` a un rango de días
/// OPERATIVOS: del día inicial a la hora de corte hasta el día siguiente al
/// final a la hora de corte (fin exclusivo).
DateTimeRange operativeRangeForPickedDays(DateTimeRange picked,
    {int? cutoffHour}) {
  final cutoff = cutoffHour ?? BusinessDayService.cachedCutoffHour;
  return DateTimeRange(
    start: DateTime(picked.start.year, picked.start.month, picked.start.day, cutoff),
    end: DateTime(picked.end.year, picked.end.month, picked.end.day + 1, cutoff),
  );
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
    this.cutoffHour,
    this.onCutoffChanged,
  });

  final DetailPeriod selected;
  final ValueChanged<DetailPeriod> onSelected;
  final Future<void> Function() onPickCustom;
  final Color? accent;
  final String? initialLabel;
  final DateTimeRange? customRange;

  /// Hora de corte del día operativo usada por los presets. Si se pasa junto
  /// con [onCutoffChanged], se muestra un chip "Corte HH:00" que permite
  /// cambiarla al momento de generar el reporte.
  final int? cutoffHour;
  final ValueChanged<int>? onCutoffChanged;

  Future<void> _pickCutoff(BuildContext context) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: cutoffHour ?? 0, minute: 0),
      helpText: 'Hora de corte del día operativo',
    );
    if (picked == null) return;
    onCutoffChanged?.call(picked.hour);
  }

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
          if (cutoffHour != null && onCutoffChanged != null) ...[
            SizedBox(width: dpi.space(6)),
            _Chip(
              label: 'Corte ${cutoffHour.toString().padLeft(2, '0')}:00',
              selected: false,
              accent: color,
              icon: Icons.schedule_rounded,
              onTap: () => _pickCutoff(context),
            ),
          ],
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
