import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/responsive/dpi_scale.dart';
import '../../../domain/catalog/promotion.dart';
import '../../../domain/catalog/promotion_enums.dart';
import '../../auth/viewmodel/auth_gate_view_model.dart';
import '../../theme/theme_data_factory.dart';
import '../viewmodel/offers_admin_view_model.dart';

/// Formulario para crear o editar una oferta "Completa" (% o monto fijo).
class PromotionFormView extends ConsumerStatefulWidget {
  const PromotionFormView({super.key, this.existing});

  /// Si no es null, edita esa oferta; si es null, crea una nueva.
  final Promotion? existing;

  @override
  ConsumerState<PromotionFormView> createState() => _PromotionFormViewState();
}

class _PromotionFormViewState extends ConsumerState<PromotionFormView> {
  final _name = TextEditingController();
  final _description = TextEditingController();
  final _value = TextEditingController();
  final _minPurchase = TextEditingController();
  final _priority = TextEditingController(text: '0');

  DiscountType _type = DiscountType.percentage;
  AppliesTo _appliesTo = AppliesTo.all;
  final Set<String> _targetIds = {};
  late DateTime _start;
  late DateTime _end;
  final Set<int> _days = {};
  bool _happyHour = false;
  TimeOfDay? _startTime;
  TimeOfDay? _endTime;
  bool _autoApply = true;
  bool _stackable = false;

  bool get _isEdit => widget.existing != null;

  /// Oferta especial (2x1/combo creada en el POS): no se edita el descuento aquí,
  /// solo el horario/estado; se preserva su tipo intacto.
  bool get _isSpecial => widget.existing != null && !widget.existing!.isSimple;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    final now = DateTime.now();
    _start = DateTime(now.year, now.month, now.day);
    _end = _start.add(const Duration(days: 30));
    if (e != null) {
      _name.text = e.name;
      _description.text = e.description;
      _value.text = _trimNum(e.discountValue);
      _minPurchase.text = e.minPurchase > 0 ? _trimNum(e.minPurchase) : '';
      _priority.text = e.priority.toString();
      _type = e.discountType;
      _appliesTo = e.appliesTo;
      _targetIds.addAll(e.targetIds);
      if (e.startDate != null) _start = e.startDate!;
      if (e.endDate != null) _end = e.endDate!;
      _days.addAll(e.daysOfWeek);
      _startTime = e.startTime;
      _endTime = e.endTime;
      _happyHour = e.startTime != null && e.endTime != null;
      _autoApply = e.autoApply;
      _stackable = e.stackable;
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _value.dispose();
    _minPurchase.dispose();
    _priority.dispose();
    super.dispose();
  }

  static String _trimNum(double v) =>
      v.truncateToDouble() == v ? v.toInt().toString() : v.toString();

  String? get _businessId => ref.read(authGateViewModelProvider).profile?.businessId;

  void _snack(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  Future<void> _save() async {
    final id = _businessId;
    if (id == null) return;

    final name = _name.text.trim();
    if (name.isEmpty) {
      _snack('Ponle un nombre a la oferta.');
      return;
    }

    // Ofertas especiales (2x1/combo): el descuento se preserva tal cual; aquí
    // solo se editan horario/estado. Las simples validan el valor.
    final existing = widget.existing;
    final double value;
    if (_isSpecial) {
      value = existing!.discountValue;
    } else {
      value = double.tryParse(_value.text.trim().replaceAll(',', '.')) ?? 0;
      if (value <= 0) {
        _snack('El valor del descuento debe ser mayor que 0.');
        return;
      }
      if (_type == DiscountType.percentage && value > 100) {
        _snack('El porcentaje no puede ser mayor que 100.');
        return;
      }
    }
    if (_end.isBefore(_start)) {
      _snack('La fecha de fin no puede ser anterior a la de inicio.');
      return;
    }
    if (_appliesTo != AppliesTo.all && _targetIds.isEmpty) {
      _snack('Selecciona al menos un ${_appliesTo == AppliesTo.product ? 'producto' : 'categoría'}.');
      return;
    }
    if (_happyHour && (_startTime == null || _endTime == null)) {
      _snack('Define la hora de inicio y fin del happy hour.');
      return;
    }

    final draft = PromotionDraft(
      name: name,
      description: _description.text.trim().isEmpty ? null : _description.text.trim(),
      discountType: _isSpecial ? existing!.discountType : _type,
      discountValue: value,
      minPurchase: double.tryParse(_minPurchase.text.trim().replaceAll(',', '.')) ?? 0,
      appliesTo: _appliesTo,
      targetIds: _appliesTo == AppliesTo.all ? const [] : _targetIds.toList(),
      daysOfWeek: _days.toList()..sort(),
      autoApply: _autoApply,
      stackable: _stackable,
      priority: int.tryParse(_priority.text.trim()) ?? 0,
      startDate: _start,
      endDate: _end,
      startTime: _happyHour ? _startTime : null,
      endTime: _happyHour ? _endTime : null,
      // Preserva el tipo y las cantidades de las ofertas especiales.
      promoType: _isSpecial ? existing!.promoType : _type.raw,
      buyQuantity: _isSpecial ? existing!.buyQuantity : null,
      payQuantity: _isSpecial ? existing!.payQuantity : null,
      rewardQuantity: _isSpecial ? existing!.rewardQuantity : null,
    );

    final notifier = ref.read(offersAdminViewModelProvider.notifier);
    final ok = _isEdit
        ? await notifier.update(id, widget.existing!.id, draft, widget.existing!.isActive)
        : await notifier.create(id, draft);

    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop();
      _snack(_isEdit ? 'Oferta actualizada.' : 'Oferta creada.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final dpi = DpiScale.of(context);
    final saving = ref.watch(offersAdminViewModelProvider).saving;

    return Scaffold(
      appBar: AppBar(title: Text(_isEdit ? 'Editar oferta' : 'Nueva oferta')),
      body: AbsorbPointer(
        absorbing: saving,
        child: ListView(
          padding: EdgeInsets.fromLTRB(dpi.space(16), dpi.space(16), dpi.space(16), dpi.space(28)),
          children: [
            _field('Nombre', TextField(controller: _name, decoration: const InputDecoration(hintText: 'Ej. Happy hour cervezas'))),
            _field('Descripción (opcional)', TextField(controller: _description, maxLines: 2, decoration: const InputDecoration(hintText: 'Detalle visible para el equipo'))),

            if (_isSpecial)
              _specialTypeInfo(context, dpi)
            else ...[
              _label(dpi, 'Tipo de descuento'),
              SegmentedButton<DiscountType>(
                segments: const [
                  ButtonSegment(value: DiscountType.percentage, label: Text('Porcentaje'), icon: Icon(Icons.percent_rounded)),
                  ButtonSegment(value: DiscountType.fixed, label: Text('Monto fijo'), icon: Icon(Icons.payments_outlined)),
                ],
                selected: {_type},
                onSelectionChanged: (s) => setState(() => _type = s.first),
              ),
              SizedBox(height: dpi.space(12)),
              _field(
                _type == DiscountType.percentage ? 'Valor (%)' : 'Valor (RD\$)',
                TextField(
                  controller: _value,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(hintText: '0'),
                ),
              ),
            ],
            _field(
              'Compra mínima',
              TextField(
                controller: _minPurchase,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(hintText: '0'),
              ),
            ),

            _label(dpi, 'Aplica a'),
            SegmentedButton<AppliesTo>(
              segments: const [
                ButtonSegment(value: AppliesTo.all, label: Text('Todo')),
                ButtonSegment(value: AppliesTo.category, label: Text('Categorías')),
                ButtonSegment(value: AppliesTo.product, label: Text('Productos')),
              ],
              selected: {_appliesTo},
              onSelectionChanged: (s) => setState(() {
                _appliesTo = s.first;
                _targetIds.clear();
              }),
            ),
            if (_appliesTo != AppliesTo.all) ...[
              SizedBox(height: dpi.space(10)),
              _targetSelector(context, dpi),
            ],

            _label(dpi, 'Vigencia'),
            Row(
              children: [
                Expanded(child: _dateField(context, dpi, 'Inicio', _start, (d) => setState(() => _start = d))),
                SizedBox(width: dpi.space(12)),
                Expanded(child: _dateField(context, dpi, 'Fin', _end, (d) => setState(() => _end = d))),
              ],
            ),

            _label(dpi, 'Días de la semana'),
            Text('Vacío = todos los días', style: TextStyle(fontSize: dpi.font(11), color: MangoThemeFactory.mutedText(context))),
            SizedBox(height: dpi.space(8)),
            Wrap(
              spacing: dpi.space(8),
              children: [
                for (var d = 0; d < 7; d++)
                  FilterChip(
                    label: Text(kWeekdayLabels[d]),
                    selected: _days.contains(d),
                    onSelected: (sel) => setState(() => sel ? _days.add(d) : _days.remove(d)),
                  ),
              ],
            ),

            _label(dpi, 'Horario'),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Happy hour (franja horaria)'),
              subtitle: Text(_happyHour ? 'Solo durante la franja' : 'Todo el día', style: TextStyle(fontSize: dpi.font(12))),
              value: _happyHour,
              activeThumbColor: MangoThemeFactory.mango,
              onChanged: (v) => setState(() => _happyHour = v),
            ),
            if (_happyHour)
              Row(
                children: [
                  Expanded(child: _timeField(context, dpi, 'Desde', _startTime, (t) => setState(() => _startTime = t))),
                  SizedBox(width: dpi.space(12)),
                  Expanded(child: _timeField(context, dpi, 'Hasta', _endTime, (t) => setState(() => _endTime = t))),
                ],
              ),

            SizedBox(height: dpi.space(8)),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Aplicar automáticamente'),
              subtitle: Text('Se aplica sola al cobrar (sin seleccionarla)', style: TextStyle(fontSize: dpi.font(12))),
              value: _autoApply,
              activeThumbColor: MangoThemeFactory.mango,
              onChanged: (v) => setState(() => _autoApply = v),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Acumulable con otras ofertas'),
              value: _stackable,
              activeThumbColor: MangoThemeFactory.mango,
              onChanged: (v) => setState(() => _stackable = v),
            ),
            _field('Prioridad', TextField(
              controller: _priority,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(hintText: '0 (mayor = se aplica primero)'),
            )),

            SizedBox(height: dpi.space(16)),
            FilledButton(
              onPressed: saving ? null : _save,
              style: FilledButton.styleFrom(
                backgroundColor: MangoThemeFactory.mango,
                foregroundColor: Colors.white,
                padding: EdgeInsets.symmetric(vertical: dpi.space(14)),
              ),
              child: saving
                  ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : Text(_isEdit ? 'Guardar cambios' : 'Crear oferta'),
            ),
          ],
        ),
      ),
    );
  }

  // ── helpers de UI ──

  Widget _specialTypeInfo(BuildContext context, DpiScale dpi) {
    final e = widget.existing!;
    return Container(
      margin: EdgeInsets.only(top: dpi.space(12)),
      padding: EdgeInsets.all(dpi.space(12)),
      decoration: BoxDecoration(
        color: MangoThemeFactory.warning.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(dpi.radius(12)),
        border: Border.all(color: MangoThemeFactory.warning.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline_rounded, size: dpi.icon(18), color: MangoThemeFactory.warning),
          SizedBox(width: dpi.space(10)),
          Expanded(
            child: Text(
              'Oferta especial (${e.specialTypeLabel}). El descuento se gestiona en el POS; '
              'aquí puedes editar horario, fechas, días y estado.',
              style: TextStyle(fontSize: dpi.font(12.5), height: 1.35, color: MangoThemeFactory.textColor(context)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _label(DpiScale dpi, String text) => Padding(
        padding: EdgeInsets.only(top: dpi.space(18), bottom: dpi.space(8)),
        child: Text(text, style: TextStyle(fontSize: dpi.font(13), fontWeight: FontWeight.w700)),
      );

  Widget _field(String label, Widget input) {
    return Builder(builder: (context) {
      final dpi = DpiScale.of(context);
      return Padding(
        padding: EdgeInsets.only(top: dpi.space(12)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: TextStyle(fontSize: dpi.font(12), color: MangoThemeFactory.mutedText(context))),
            SizedBox(height: dpi.space(6)),
            input,
          ],
        ),
      );
    });
  }

  Widget _dateField(BuildContext context, DpiScale dpi, String label, DateTime value, ValueChanged<DateTime> onPick) {
    return InkWell(
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: value,
          firstDate: DateTime(2020),
          lastDate: DateTime(2100),
        );
        if (picked != null) onPick(picked);
      },
      child: InputDecorator(
        decoration: InputDecoration(labelText: label, suffixIcon: const Icon(Icons.calendar_today_rounded, size: 18)),
        child: Text('${value.day.toString().padLeft(2, '0')}/${value.month.toString().padLeft(2, '0')}/${value.year}'),
      ),
    );
  }

  Widget _timeField(BuildContext context, DpiScale dpi, String label, TimeOfDay? value, ValueChanged<TimeOfDay> onPick) {
    return InkWell(
      onTap: () async {
        final picked = await showTimePicker(context: context, initialTime: value ?? const TimeOfDay(hour: 17, minute: 0));
        if (picked != null) onPick(picked);
      },
      child: InputDecorator(
        decoration: InputDecoration(labelText: label, suffixIcon: const Icon(Icons.schedule_rounded, size: 18)),
        child: Text(value == null ? '--:--' : '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}'),
      ),
    );
  }

  Widget _targetSelector(BuildContext context, DpiScale dpi) {
    final vm = ref.watch(offersAdminViewModelProvider);
    final isProduct = _appliesTo == AppliesTo.product;
    final entries = isProduct
        ? [for (final p in vm.products) (id: p.id, name: p.name)]
        : [for (final c in vm.categories) (id: c.id, name: c.name)];
    final selectedNames = entries.where((e) => _targetIds.contains(e.id)).map((e) => e.name).toList();

    return InkWell(
      onTap: () async {
        final result = await showDialog<Set<String>>(
          context: context,
          builder: (_) => _TargetPickerDialog(
            title: isProduct ? 'Selecciona productos' : 'Selecciona categorías',
            entries: entries,
            initial: _targetIds,
          ),
        );
        if (result != null) setState(() => _targetIds..clear()..addAll(result));
      },
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: isProduct ? 'Productos' : 'Categorías',
          suffixIcon: const Icon(Icons.chevron_right_rounded),
        ),
        child: Text(
          selectedNames.isEmpty ? 'Seleccionar…' : selectedNames.join(', '),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }
}

/// Diálogo multi-selección con búsqueda, para productos o categorías.
class _TargetPickerDialog extends StatefulWidget {
  const _TargetPickerDialog({required this.title, required this.entries, required this.initial});

  final String title;
  final List<({String id, String name})> entries;
  final Set<String> initial;

  @override
  State<_TargetPickerDialog> createState() => _TargetPickerDialogState();
}

class _TargetPickerDialogState extends State<_TargetPickerDialog> {
  late final Set<String> _selected = {...widget.initial};
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final filtered = _q.isEmpty
        ? widget.entries
        : widget.entries.where((e) => e.name.toLowerCase().contains(_q.toLowerCase())).toList();

    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              onChanged: (v) => setState(() => _q = v),
              decoration: const InputDecoration(hintText: 'Buscar…', prefixIcon: Icon(Icons.search_rounded)),
            ),
            const SizedBox(height: 8),
            Flexible(
              child: filtered.isEmpty
                  ? const Padding(padding: EdgeInsets.all(16), child: Text('Sin resultados.'))
                  : ListView.builder(
                      shrinkWrap: true,
                      itemCount: filtered.length,
                      itemBuilder: (_, i) {
                        final e = filtered[i];
                        final sel = _selected.contains(e.id);
                        return CheckboxListTile(
                          dense: true,
                          value: sel,
                          title: Text(e.name),
                          onChanged: (v) => setState(() => v == true ? _selected.add(e.id) : _selected.remove(e.id)),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(onPressed: () => Navigator.pop(context, _selected), child: const Text('Listo')),
      ],
    );
  }
}
