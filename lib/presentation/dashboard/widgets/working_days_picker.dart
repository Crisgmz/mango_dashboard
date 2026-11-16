import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/responsive/dpi_scale.dart';
import '../../../data/dashboard/working_days.dart';
import '../../theme/theme_data_factory.dart';
import '../viewmodel/working_days_controller.dart';

/// Diálogo para elegir los días que abre el negocio. Devuelve la selección o
/// null si se cancela.
Future<Set<int>?> showWorkingDaysDialog(BuildContext context, Set<int> initial) {
  return showDialog<Set<int>>(
    context: context,
    builder: (_) => _WorkingDaysDialog(initial: initial),
  );
}

/// Abre el diálogo con los días actuales de [businessId], guarda la selección
/// y lo confirma con un SnackBar. Todas las proyecciones que observan
/// [workingDaysProvider] se recalculan solas.
Future<void> editWorkingDays(BuildContext context, WidgetRef ref, String businessId) async {
  final current = ref.read(workingDaysProvider(businessId));
  final picked = await showWorkingDaysDialog(context, current);
  if (picked == null) return;
  await ref.read(workingDaysProvider(businessId).notifier).set(picked);
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text('Días laborables: ${workingDaysLabel(picked)}.')),
  );
}

class _WorkingDaysDialog extends StatefulWidget {
  const _WorkingDaysDialog({required this.initial});
  final Set<int> initial;

  @override
  State<_WorkingDaysDialog> createState() => _WorkingDaysDialogState();
}

class _WorkingDaysDialogState extends State<_WorkingDaysDialog> {
  late Set<int> _days = {...widget.initial};

  static const _presets = <(String, Set<int>)>[
    ('Lun–Vie', {1, 2, 3, 4, 5}),
    ('Lun–Sáb', {1, 2, 3, 4, 5, 6}),
    ('Todos', kAllWeekdays),
  ];

  void _toggle(int day) {
    setState(() => _days.contains(day) ? _days.remove(day) : _days.add(day));
  }

  @override
  Widget build(BuildContext context) {
    final dpi = DpiScale.of(context);
    final muted = MangoThemeFactory.mutedText(context);
    return AlertDialog(
      title: const Text('Días laborables'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Las proyecciones del mes solo cuentan los días que abre el negocio.',
            style: TextStyle(fontSize: dpi.font(12), color: muted, height: 1.35),
          ),
          SizedBox(height: dpi.space(14)),
          Wrap(
            spacing: dpi.space(6),
            runSpacing: dpi.space(6),
            children: [
              for (var d = 1; d <= 7; d++)
                _DayToggle(
                  label: kWeekdayShortEs[d - 1],
                  selected: _days.contains(d),
                  onTap: () => _toggle(d),
                ),
            ],
          ),
          SizedBox(height: dpi.space(12)),
          Wrap(
            spacing: dpi.space(4),
            children: [
              for (final (label, preset) in _presets)
                TextButton(
                  onPressed: () => setState(() => _days = {...preset}),
                  child: Text(label),
                ),
            ],
          ),
          if (_days.isEmpty)
            Text(
              'Elige al menos un día.',
              style: TextStyle(fontSize: dpi.font(11), color: MangoThemeFactory.danger),
            )
          else
            Text(
              workingDaysLabel(_days),
              style: TextStyle(fontSize: dpi.font(12), fontWeight: FontWeight.w700, color: muted),
            ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(
          onPressed: _days.isEmpty ? null : () => Navigator.pop(context, _days),
          child: const Text('Guardar'),
        ),
      ],
    );
  }
}

class _DayToggle extends StatelessWidget {
  const _DayToggle({required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final dpi = DpiScale.of(context);
    final radius = BorderRadius.circular(dpi.radius(12));
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: radius,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: dpi.scale(44),
          height: dpi.scale(40),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected
                ? MangoThemeFactory.mango.withValues(alpha: 0.12)
                : MangoThemeFactory.altSurface(context),
            borderRadius: radius,
            border: Border.all(
              color: selected ? MangoThemeFactory.mango : MangoThemeFactory.borderColor(context),
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: dpi.font(12),
              fontWeight: FontWeight.w700,
              color: selected ? MangoThemeFactory.mango : MangoThemeFactory.mutedText(context),
            ),
          ),
        ),
      ),
    );
  }
}

/// Píldora tocable con los días laborables ("Lunes a sábado") para cambiarlos
/// desde una tarjeta de proyección.
class WorkingDaysPill extends StatelessWidget {
  const WorkingDaysPill({super.key, required this.workingDays, required this.onTap});
  final Set<int> workingDays;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final dpi = DpiScale.of(context);
    final muted = MangoThemeFactory.mutedText(context);
    final radius = BorderRadius.circular(dpi.radius(20));
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: radius,
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: dpi.space(8), vertical: dpi.space(4)),
          decoration: BoxDecoration(
            color: MangoThemeFactory.altSurface(context),
            borderRadius: radius,
            border: Border.all(color: MangoThemeFactory.borderColor(context)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.event_available_rounded, size: dpi.icon(13), color: muted),
              SizedBox(width: dpi.space(4)),
              Flexible(
                child: Text(
                  workingDaysLabel(workingDays),
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: dpi.font(11), fontWeight: FontWeight.w600, color: muted),
                ),
              ),
              if (onTap != null) Icon(Icons.expand_more_rounded, size: dpi.icon(14), color: muted),
            ],
          ),
        ),
      ),
    );
  }
}
