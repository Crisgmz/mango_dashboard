import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/responsive/dpi_scale.dart';
import '../../../domain/floor/floor_models.dart';
import '../../theme/theme_data_factory.dart';
import '../viewmodel/floor_admin_view_model.dart';

/// Nombre de una zona (crear o renombrar). Devuelve el nombre o null.
Future<String?> showZoneNameDialog(
  BuildContext context, {
  FloorZone? existing,
}) {
  return showDialog<String>(
    context: context,
    builder: (_) => _ZoneNameDialog(existing: existing),
  );
}

class _ZoneNameDialog extends StatefulWidget {
  const _ZoneNameDialog({this.existing});

  final FloorZone? existing;

  @override
  State<_ZoneNameDialog> createState() => _ZoneNameDialogState();
}

class _ZoneNameDialogState extends State<_ZoneNameDialog> {
  late final TextEditingController _name = TextEditingController(
    text: widget.existing?.name ?? '',
  );
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _save() {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Escribe el nombre.');
      return;
    }
    Navigator.pop(context, name);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.existing?.name ?? 'Nueva zona'),
      content: TextField(
        controller: _name,
        autofocus: true,
        textCapitalization: TextCapitalization.sentences,
        onSubmitted: (_) => _save(),
        decoration: InputDecoration(
          labelText: 'Nombre de la zona',
          hintText: 'Ej. Terraza',
          errorText: _error,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _save,
          child: Text(widget.existing == null ? 'Crear' : 'Guardar'),
        ),
      ],
    );
  }
}

/// Resultado del diálogo de mesa.
class TableDialogResult {
  const TableDialogResult.save({
    required this.code,
    required this.label,
    required this.capacity,
    required this.zoneId,
  }) : delete = false;

  const TableDialogResult.delete()
    : code = '',
      label = null,
      capacity = 0,
      zoneId = '',
      delete = true;

  final String code;
  final String? label;
  final int capacity;
  final String zoneId;
  final bool delete;
}

/// Crear o editar una mesa. Al editar permite moverla a otra zona y
/// eliminarla (si está libre).
Future<TableDialogResult?> showTableDialog(
  BuildContext context, {
  required String zoneId,
  required List<FloorZone> zones,
  FloorTable? existing,
}) {
  return showDialog<TableDialogResult>(
    context: context,
    builder: (_) =>
        _TableDialog(zoneId: zoneId, zones: zones, existing: existing),
  );
}

class _TableDialog extends StatefulWidget {
  const _TableDialog({
    required this.zoneId,
    required this.zones,
    this.existing,
  });

  final String zoneId;
  final List<FloorZone> zones;
  final FloorTable? existing;

  @override
  State<_TableDialog> createState() => _TableDialogState();
}

class _TableDialogState extends State<_TableDialog> {
  late final TextEditingController _code = TextEditingController(
    text: widget.existing?.code ?? '',
  );
  late final TextEditingController _label = TextEditingController(
    // Si el nombre es el mismo código (lo que guarda el POS por defecto), el
    // campo queda vacío para no duplicar.
    text:
        (widget.existing?.label != null &&
            widget.existing!.label != widget.existing!.code)
        ? widget.existing!.label
        : '',
  );
  late final TextEditingController _capacity = TextEditingController(
    text: '${widget.existing?.capacity ?? 4}',
  );
  late String _zoneId = widget.zoneId;
  String? _codeError;
  String? _capacityError;

  @override
  void dispose() {
    _code.dispose();
    _label.dispose();
    _capacity.dispose();
    super.dispose();
  }

  void _save() {
    final code = _code.text.trim();
    final capacity = int.tryParse(_capacity.text.trim());
    setState(() {
      _codeError = code.isEmpty ? 'Escribe el código.' : null;
      _capacityError = (capacity == null || capacity < 1 || capacity > 50)
          ? 'Entre 1 y 50.'
          : null;
    });
    if (_codeError != null || _capacityError != null) return;
    final label = _label.text.trim();
    Navigator.pop(
      context,
      TableDialogResult.save(
        code: code,
        label: label.isEmpty ? null : label,
        capacity: capacity!,
        zoneId: _zoneId,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dpi = DpiScale.of(context);
    final existing = widget.existing;
    final muted = MangoThemeFactory.mutedText(context);

    return AlertDialog(
      title: Text(existing?.displayName ?? 'Nueva mesa'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _code,
              autofocus: existing == null,
              textCapitalization: TextCapitalization.characters,
              decoration: InputDecoration(
                labelText: 'Código',
                hintText: 'Ej. T05',
                helperText: 'Único dentro de la zona.',
                errorText: _codeError,
              ),
            ),
            SizedBox(height: dpi.space(12)),
            TextField(
              controller: _label,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Nombre en el POS (opcional)',
                hintText: 'Ej. Terraza 5',
                helperText: 'Si lo dejas vacío, el POS muestra el código.',
              ),
            ),
            SizedBox(height: dpi.space(12)),
            TextField(
              controller: _capacity,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(
                labelText: 'Personas',
                errorText: _capacityError,
              ),
            ),
            if (existing != null && widget.zones.length > 1) ...[
              SizedBox(height: dpi.space(12)),
              DropdownButtonFormField<String>(
                initialValue: _zoneId,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Zona'),
                items: [
                  for (final z in widget.zones)
                    DropdownMenuItem(
                      value: z.id,
                      child: Text(z.name, overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: (v) => setState(() => _zoneId = v ?? _zoneId),
              ),
              if (_zoneId != widget.zoneId && !existing.isAvailable) ...[
                SizedBox(height: dpi.space(6)),
                Text(
                  'La cuenta abierta se mueve con la mesa.',
                  style: TextStyle(fontSize: dpi.font(11.5), color: muted),
                ),
              ],
            ],
            if (existing != null) ...[
              SizedBox(height: dpi.space(12)),
              if (existing.isAvailable)
                TextButton.icon(
                  onPressed: () =>
                      Navigator.pop(context, const TableDialogResult.delete()),
                  style: TextButton.styleFrom(
                    foregroundColor: MangoThemeFactory.danger,
                  ),
                  icon: Icon(Icons.delete_outline_rounded, size: dpi.icon(18)),
                  label: const Text('Eliminar mesa'),
                )
              else
                Text(
                  'Está ${existing.stateLabel!.toLowerCase()}: libérala en el POS para poder eliminarla.',
                  style: TextStyle(fontSize: dpi.font(11.5), color: muted),
                ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _save,
          child: Text(existing == null ? 'Crear' : 'Guardar'),
        ),
      ],
    );
  }
}

/// Datos para crear varias mesas (`prefijo + número`).
typedef BulkTablesInput = ({String prefix, int from, int to, int capacity});

Future<BulkTablesInput?> showBulkTablesDialog(BuildContext context) {
  return showDialog<BulkTablesInput>(
    context: context,
    builder: (_) => const _BulkTablesDialog(),
  );
}

class _BulkTablesDialog extends StatefulWidget {
  const _BulkTablesDialog();

  @override
  State<_BulkTablesDialog> createState() => _BulkTablesDialogState();
}

class _BulkTablesDialogState extends State<_BulkTablesDialog> {
  final _prefix = TextEditingController(text: 'T');
  final _from = TextEditingController(text: '1');
  final _to = TextEditingController(text: '10');
  final _capacity = TextEditingController(text: '4');
  String? _error;

  @override
  void dispose() {
    _prefix.dispose();
    _from.dispose();
    _to.dispose();
    _capacity.dispose();
    super.dispose();
  }

  BulkTablesInput? _parse() {
    final prefix = _prefix.text.trim();
    final from = int.tryParse(_from.text.trim());
    final to = int.tryParse(_to.text.trim());
    final capacity = int.tryParse(_capacity.text.trim());
    if (prefix.isEmpty || from == null || to == null || capacity == null) {
      return null;
    }
    return (prefix: prefix, from: from, to: to, capacity: capacity);
  }

  String get _preview {
    final input = _parse();
    if (input == null || input.from < 1 || input.to < input.from) {
      return 'Completa el prefijo y un rango válido.';
    }
    final count = input.to - input.from + 1;
    final first = bulkTableCode(input.prefix, input.from, input.to);
    final last = bulkTableCode(input.prefix, input.to, input.to);
    return count == 1
        ? 'Se creará $first.'
        : 'Se crearán $count mesas: $first … $last. Las que ya existan se saltan.';
  }

  void _save() {
    final input = _parse();
    if (input == null) {
      setState(() => _error = 'Completa todos los campos.');
      return;
    }
    Navigator.pop(context, input);
  }

  @override
  Widget build(BuildContext context) {
    final dpi = DpiScale.of(context);
    Widget number(TextEditingController c, String label) => Expanded(
      child: TextField(
        controller: c,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(labelText: label),
      ),
    );

    return AlertDialog(
      title: const Text('Crear varias mesas'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _prefix,
              autofocus: true,
              textCapitalization: TextCapitalization.characters,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: 'Prefijo',
                hintText: 'Ej. T',
              ),
            ),
            SizedBox(height: dpi.space(12)),
            Row(
              children: [
                number(_from, 'Desde'),
                SizedBox(width: dpi.space(10)),
                number(_to, 'Hasta'),
                SizedBox(width: dpi.space(10)),
                number(_capacity, 'Personas'),
              ],
            ),
            SizedBox(height: dpi.space(12)),
            Text(
              _error ?? _preview,
              style: TextStyle(
                fontSize: dpi.font(12),
                color: _error != null
                    ? MangoThemeFactory.danger
                    : MangoThemeFactory.mutedText(context),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(onPressed: _save, child: const Text('Crear')),
      ],
    );
  }
}

/// Confirmación de eliminar (zona o mesa). [detail] explica qué pasa si hay
/// historial. Devuelve true si confirma.
Future<bool> confirmFloorDelete(
  BuildContext context, {
  required String title,
  required String detail,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(detail),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          style: FilledButton.styleFrom(
            backgroundColor: MangoThemeFactory.danger,
          ),
          child: const Text('Eliminar'),
        ),
      ],
    ),
  );
  return ok == true;
}
