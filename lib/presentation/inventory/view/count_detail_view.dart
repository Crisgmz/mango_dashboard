import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/di/providers.dart';
import '../../../core/formatters/mango_formatters.dart';
import '../../../core/responsive/dpi_scale.dart';
import '../../../domain/inventory/physical_count_models.dart';
import '../../purchasing/view/reception_scanner_page.dart';
import '../../theme/theme_data_factory.dart';

/// Detalle de un conteo físico (PRD 6.1 F5): contar con escáner o manual
/// (modo ciego oculta el snapshot), revisar varianzas en cantidad y RD$, y
/// completar — genera ajustes SOLO de lo contado; lo no contado mantiene su
/// stock (semántica de conteo cíclico).
class CountDetailView extends ConsumerStatefulWidget {
  const CountDetailView({super.key, required this.sessionId});

  final String sessionId;

  @override
  ConsumerState<CountDetailView> createState() => _CountDetailViewState();
}

class _CountDetailViewState extends ConsumerState<CountDetailView> {
  CountSession? _session;
  List<CountLine> _lines = const [];
  Map<String, String> _codeToItem = const {};
  String _query = '';
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    try {
      final service = ref.read(physicalCountServiceProvider);
      final results = await Future.wait([
        service.loadSession(widget.sessionId),
        service.loadLines(widget.sessionId),
      ]);
      final lines = results[1] as List<CountLine>;
      Map<String, String> codes = const {};
      try {
        codes = await ref.read(purchasingDataServiceProvider).loadItemCodes(
            lines.map((l) => l.itemId).toList(growable: false));
      } catch (_) {/* escáner deshabilitado */}
      if (!mounted) return;
      setState(() {
        _session = results[0] as CountSession;
        _lines = lines;
        _codeToItem = codes;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _snack(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  List<CountLine> get _visible {
    if (_query.isEmpty) return _lines;
    final q = _query.toLowerCase();
    return _lines
        .where((l) => (l.itemName ?? '').toLowerCase().contains(q))
        .toList(growable: false);
  }

  int get _countedCount => _lines.where((l) => l.isCounted).length;

  Future<void> _setCount(CountLine line, double value) async {
    try {
      await ref.read(physicalCountServiceProvider).setCount(
            sessionId: widget.sessionId,
            itemId: line.itemId,
            countedQuantity: value,
          );
      final lines =
          await ref.read(physicalCountServiceProvider).loadLines(widget.sessionId);
      if (mounted) setState(() => _lines = lines);
    } catch (_) {
      _snack('No se pudo guardar el conteo de "${line.itemName ?? 'ítem'}".');
    }
  }

  Future<void> _editCount(CountLine line) async {
    final session = _session;
    if (session == null || !session.isOpen) return;
    final controller = TextEditingController(
        text: line.countedQuantity != null
            ? _trim(line.countedQuantity!)
            : '');
    final value = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(line.itemName ?? 'Contar'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!session.isBlind)
              Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    'Sistema: ${MangoFormatters.number(line.snapshotQuantity)} ${line.unit ?? ''}',
                    style: TextStyle(
                        color: MangoThemeFactory.mutedText(ctx),
                        fontSize: 12.5),
                  ),
                ),
              ),
            TextField(
              controller: controller,
              autofocus: true,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: 'Cantidad contada (${line.unit ?? 'u'})',
              ),
            ),
          ],
        ),
        actions: [
          if (!session.isBlind)
            TextButton(
              onPressed: () =>
                  Navigator.of(ctx).pop(line.snapshotQuantity),
              child: const Text('= Sistema'),
            ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              final v = double.tryParse(
                  controller.text.trim().replaceAll(',', '.'));
              if (v == null || v < 0) return;
              Navigator.of(ctx).pop(v);
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (value == null) return;
    await _setCount(line, value);
  }

  /// Cada escaneo suma 1 al contado del ítem (arranca en 1 si no se había
  /// contado).
  ScanFeedback? _handleScan(String code) {
    final itemId = _codeToItem[code];
    if (itemId == null) {
      return const ScanFeedback(
          matched: false, message: 'Código no está en este conteo');
    }
    final line = _lines.where((l) => l.itemId == itemId).firstOrNull;
    if (line == null) {
      return const ScanFeedback(matched: false, message: 'Ítem no encontrado');
    }
    final next = (line.countedQuantity ?? 0) + 1;
    // Optimista en UI; el RPC persiste en segundo plano.
    _setCount(line, next);
    return ScanFeedback(
      matched: true,
      message:
          '${line.itemName ?? 'Ítem'} · ${MangoFormatters.number(next)} ${line.unit ?? ''}',
    );
  }

  Future<void> _openScanner() async {
    if (_codeToItem.isEmpty) {
      _snack('Ningún ítem del conteo tiene código de barras ni SKU.');
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ReceptionScannerPage(onCode: _handleScan),
      ),
    );
    if (mounted) _load();
  }

  Future<void> _complete() async {
    final variances =
        _lines.where((l) => (l.variance ?? 0) != 0).length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Completar conteo'),
        content: Text(
          'Se registraron $_countedCount de ${_lines.length} líneas'
          '${variances > 0 ? ', con $variances diferencia(s) que generarán ajustes de inventario' : ''}. '
          'Las líneas sin contar mantienen su stock. ¿Completar?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Seguir contando'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Completar'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _saving = true);
    try {
      await ref.read(physicalCountServiceProvider).complete(widget.sessionId);
      if (!mounted) return;
      _snack('Conteo completado: los ajustes quedaron aplicados.');
      _load();
    } catch (_) {
      if (mounted) _snack('No se pudo completar el conteo.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _cancel() async {
    final controller = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancelar conteo'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Motivo (opcional)'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Volver'),
          ),
          FilledButton(
            style:
                FilledButton.styleFrom(backgroundColor: MangoThemeFactory.danger),
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            child: const Text('Cancelar conteo'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (reason == null || !mounted) return;
    try {
      await ref
          .read(physicalCountServiceProvider)
          .cancel(widget.sessionId, reason: reason.isEmpty ? null : reason);
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (_) {
      if (mounted) _snack('No se pudo cancelar el conteo.');
    }
  }

  static String _trim(double v) =>
      v.truncateToDouble() == v ? v.toInt().toString() : v.toString();

  @override
  Widget build(BuildContext context) {
    final dpi = DpiScale.of(context);
    final session = _session;
    final open = session?.isOpen ?? false;
    final completed = session?.status == 'completed';

    return Scaffold(
      appBar: AppBar(
        title: Text(session?.code ?? 'Conteo'),
        centerTitle: false,
        actions: [
          if (open) ...[
            IconButton(
              tooltip: 'Escanear con cámara',
              icon: const Icon(Icons.qr_code_scanner_rounded),
              onPressed: _openScanner,
            ),
            IconButton(
              tooltip: 'Cancelar conteo',
              icon: Icon(Icons.cancel_outlined,
                  color: MangoThemeFactory.danger),
              onPressed: _cancel,
            ),
          ],
        ],
      ),
      bottomNavigationBar: !open || _loading
          ? null
          : SafeArea(
              child: Container(
                padding: EdgeInsets.fromLTRB(
                    dpi.space(16), dpi.space(10), dpi.space(16), dpi.space(12)),
                decoration: BoxDecoration(
                  color: MangoThemeFactory.cardColor(context),
                  border: Border(
                    top: BorderSide(
                        color: MangoThemeFactory.borderColor(context)),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Contadas $_countedCount de ${_lines.length}',
                            style: TextStyle(
                                fontSize: dpi.font(11.5),
                                fontWeight: FontWeight.w700),
                          ),
                          SizedBox(height: dpi.space(4)),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(999),
                            child: LinearProgressIndicator(
                              value: _lines.isEmpty
                                  ? 0
                                  : _countedCount / _lines.length,
                              minHeight: dpi.scale(5),
                              backgroundColor: MangoThemeFactory.mango
                                  .withValues(alpha: 0.15),
                              valueColor: const AlwaysStoppedAnimation<Color>(
                                  MangoThemeFactory.mango),
                            ),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(width: dpi.space(12)),
                    FilledButton.icon(
                      onPressed: _saving ? null : _complete,
                      style: FilledButton.styleFrom(
                        backgroundColor: MangoThemeFactory.success,
                        padding: EdgeInsets.symmetric(
                            horizontal: dpi.space(18),
                            vertical: dpi.space(14)),
                      ),
                      icon: _saving
                          ? SizedBox(
                              width: dpi.icon(16),
                              height: dpi.icon(16),
                              child: const CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.check_circle_rounded),
                      label: Text(_saving ? 'Aplicando…' : 'Completar'),
                    ),
                  ],
                ),
              ),
            ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : session == null
              ? Center(
                  child: Text('No se pudo cargar el conteo.',
                      style: TextStyle(color: MangoThemeFactory.danger)))
              : ListView(
                  padding: EdgeInsets.all(dpi.space(16)),
                  children: [
                    if (session.isBlind && open)
                      Container(
                        margin: EdgeInsets.only(bottom: dpi.space(12)),
                        padding: EdgeInsets.all(dpi.space(10)),
                        decoration: BoxDecoration(
                          color:
                              MangoThemeFactory.info.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(dpi.radius(10)),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.visibility_off_rounded,
                                size: dpi.icon(16),
                                color: MangoThemeFactory.info),
                            SizedBox(width: dpi.space(8)),
                            Expanded(
                              child: Text(
                                'Conteo ciego: la cantidad del sistema se revela al completar.',
                                style: TextStyle(
                                    fontSize: dpi.font(11.5),
                                    color: MangoThemeFactory.info),
                              ),
                            ),
                          ],
                        ),
                      ),
                    if (completed) _VarianceSummary(lines: _lines),
                    TextField(
                      onChanged: (v) => setState(() => _query = v),
                      decoration: const InputDecoration(
                        hintText: 'Buscar ítem…',
                        prefixIcon: Icon(Icons.search_rounded),
                        isDense: true,
                      ),
                    ),
                    SizedBox(height: dpi.space(10)),
                    ..._visible.map((l) => _LineTile(
                          line: l,
                          blind: session.isBlind && open,
                          completed: completed,
                          onTap: open ? () => _editCount(l) : null,
                        )),
                    SizedBox(height: dpi.space(24)),
                  ],
                ),
    );
  }
}

/// Resumen de varianzas del conteo completado: faltantes y sobrantes en RD$.
class _VarianceSummary extends StatelessWidget {
  const _VarianceSummary({required this.lines});

  final List<CountLine> lines;

  @override
  Widget build(BuildContext context) {
    final dpi = DpiScale.of(context);
    var shortageCost = 0.0;
    var overageCost = 0.0;
    var diffs = 0;
    for (final l in lines) {
      final vc = l.varianceCost;
      if (vc == null || vc == 0) continue;
      diffs++;
      if (vc < 0) {
        shortageCost += -vc;
      } else {
        overageCost += vc;
      }
    }
    return Container(
      margin: EdgeInsets.only(bottom: dpi.space(12)),
      padding: EdgeInsets.all(dpi.space(14)),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [
          MangoThemeFactory.success,
          MangoThemeFactory.success.withValues(alpha: 0.8),
        ]),
        borderRadius: BorderRadius.circular(dpi.radius(16)),
      ),
      child: Row(
        children: [
          Expanded(
            child: _stat(dpi, 'Diferencias', '$diffs'),
          ),
          Expanded(
            child: _stat(dpi, 'Faltante',
                '−${MangoFormatters.currency(shortageCost)}'),
          ),
          Expanded(
            child: _stat(dpi, 'Sobrante',
                '+${MangoFormatters.currency(overageCost)}'),
          ),
        ],
      ),
    );
  }

  Widget _stat(DpiScale dpi, String label, String value) {
    return Column(
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(value,
              style: TextStyle(
                  color: Colors.white,
                  fontSize: dpi.font(14),
                  fontWeight: FontWeight.w800)),
        ),
        SizedBox(height: dpi.space(2)),
        Text(label,
            style: TextStyle(color: Colors.white70, fontSize: dpi.font(10))),
      ],
    );
  }
}

class _LineTile extends StatelessWidget {
  const _LineTile({
    required this.line,
    required this.blind,
    required this.completed,
    this.onTap,
  });

  final CountLine line;
  final bool blind;
  final bool completed;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final dpi = DpiScale.of(context);
    final variance = line.variance;
    final hasDiff = variance != null && variance != 0;
    final diffColor = !hasDiff
        ? MangoThemeFactory.success
        : variance < 0
            ? MangoThemeFactory.danger
            : MangoThemeFactory.warning;

    return Container(
      margin: EdgeInsets.only(bottom: dpi.space(6)),
      decoration: BoxDecoration(
        color: MangoThemeFactory.cardColor(context),
        borderRadius: BorderRadius.circular(dpi.radius(12)),
        border: Border.all(
          color: completed && hasDiff
              ? diffColor.withValues(alpha: 0.45)
              : MangoThemeFactory.borderColor(context),
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(dpi.radius(12)),
          child: Padding(
            padding: EdgeInsets.symmetric(
                horizontal: dpi.space(14), vertical: dpi.space(10)),
            child: Row(
              children: [
                Icon(
                  line.isCounted
                      ? Icons.check_circle_rounded
                      : Icons.radio_button_unchecked_rounded,
                  size: dpi.icon(18),
                  color: line.isCounted
                      ? MangoThemeFactory.success
                      : MangoThemeFactory.mutedText(context)
                          .withValues(alpha: 0.5),
                ),
                SizedBox(width: dpi.space(10)),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        line.itemName ?? 'Ítem',
                        style: TextStyle(
                          fontSize: dpi.font(13),
                          fontWeight: FontWeight.w600,
                          color: MangoThemeFactory.textColor(context),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      SizedBox(height: dpi.space(1)),
                      Text(
                        blind
                            ? (line.isCounted
                                ? 'Contado: ${MangoFormatters.number(line.countedQuantity!)} ${line.unit ?? ''}'
                                : 'Sin contar')
                            : 'Sistema: ${MangoFormatters.number(line.snapshotQuantity)} ${line.unit ?? ''}'
                                '${line.isCounted ? ' · Contado: ${MangoFormatters.number(line.countedQuantity!)}' : ''}',
                        style: TextStyle(
                          fontSize: dpi.font(11),
                          color: MangoThemeFactory.mutedText(context),
                        ),
                      ),
                    ],
                  ),
                ),
                if (completed && hasDiff)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '${variance > 0 ? '+' : ''}${MangoFormatters.number(variance)}',
                        style: TextStyle(
                          fontSize: dpi.font(13),
                          fontWeight: FontWeight.w800,
                          color: diffColor,
                        ),
                      ),
                      if (line.varianceCost != null)
                        Text(
                          '${line.varianceCost! > 0 ? '+' : '−'}${MangoFormatters.currency(line.varianceCost!.abs())}',
                          style: TextStyle(
                            fontSize: dpi.font(10.5),
                            color: diffColor,
                          ),
                        ),
                    ],
                  )
                else if (onTap != null)
                  Icon(Icons.edit_rounded,
                      size: dpi.icon(16),
                      color: MangoThemeFactory.mutedText(context)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
