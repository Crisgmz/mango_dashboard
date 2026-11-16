import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/di/providers.dart';
import '../../../core/responsive/dpi_scale.dart';
import '../../../data/settings/sales_note_settings_service.dart';
import '../../theme/theme_data_factory.dart';

/// Ajustes → Facturación: encender la nota de venta del negocio y su prefijo.
/// Es el ÚNICO lugar donde se cambia; la POS solo lo lee.
class SalesNoteSettingsCard extends ConsumerStatefulWidget {
  const SalesNoteSettingsCard({super.key, required this.businessId});

  final String businessId;

  @override
  ConsumerState<SalesNoteSettingsCard> createState() => _SalesNoteSettingsCardState();
}

class _SalesNoteSettingsCardState extends ConsumerState<SalesNoteSettingsCard> {
  final _prefix = TextEditingController();
  SalesNoteSettings? _settings;
  bool _loadFailed = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant SalesNoteSettingsCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.businessId != widget.businessId) _load();
  }

  @override
  void dispose() {
    _prefix.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _settings = null;
      _loadFailed = false;
    });
    if (widget.businessId.isEmpty) return;
    final businessId = widget.businessId;
    try {
      final settings = await ref.read(salesNoteSettingsServiceProvider).load(businessId);
      if (!mounted || businessId != widget.businessId) return;
      setState(() {
        _settings = settings;
        _prefix.text = settings.prefix;
      });
    } catch (_) {
      if (!mounted || businessId != widget.businessId) return;
      setState(() => _loadFailed = true);
    }
  }

  /// Guarda y, si falla, vuelve a lo que había: el switch nunca queda
  /// mostrando algo que no está en la base.
  Future<void> _save(SalesNoteSettings next, String okMessage) async {
    final previous = _settings;
    if (previous == null || _saving) return;
    setState(() {
      _saving = true;
      _settings = next;
      _prefix.text = next.prefix;
    });
    try {
      await ref.read(salesNoteSettingsServiceProvider).save(widget.businessId, next);
      if (!mounted) return;
      _snack(okMessage);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _settings = previous;
        _prefix.text = previous.prefix;
      });
      _snack('No se pudo guardar. Revisa la conexión e intenta de nuevo.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _savePrefix() {
    final current = _settings;
    if (current == null) return;
    final value = SalesNoteSettings.normalizePrefix(_prefix.text);
    if (value == current.prefix) {
      _prefix.text = value;
      return;
    }
    _save(current.copyWith(prefix: value), 'Prefijo guardado: ${value}000123.');
  }

  void _snack(String text) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text), behavior: SnackBarBehavior.floating),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dpi = DpiScale.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final settings = _settings;
    final muted = MangoThemeFactory.mutedText(context);

    return Container(
      padding: EdgeInsets.all(dpi.space(16)),
      decoration: BoxDecoration(
        color: MangoThemeFactory.cardColor(context),
        borderRadius: BorderRadius.circular(dpi.radius(20)),
        border: Border.all(color: MangoThemeFactory.borderColor(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: dpi.scale(44),
                height: dpi.scale(44),
                decoration: BoxDecoration(
                  color: MangoThemeFactory.mango.withValues(alpha: isDark ? 0.2 : 0.12),
                  borderRadius: BorderRadius.circular(dpi.radius(12)),
                ),
                child: Icon(Icons.receipt_long_rounded, color: MangoThemeFactory.mango, size: dpi.icon(24)),
              ),
              SizedBox(width: dpi.space(12)),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Vender por nota de venta',
                      style: TextStyle(fontSize: dpi.font(14), fontWeight: FontWeight.w700),
                    ),
                    SizedBox(height: dpi.space(2)),
                    Text(
                      'Documento sin valor fiscal para el cliente que no pide comprobante. '
                      'El cajero lo elige en cada cobro en efectivo a consumidor final; '
                      'el cobro siempre arranca con factura. No consume NCF ni va al 607: '
                      'su total se declara aparte.',
                      style: TextStyle(fontSize: dpi.font(11), color: muted, height: 1.35),
                    ),
                  ],
                ),
              ),
              SizedBox(width: dpi.space(8)),
              if (settings != null)
                Switch(
                  value: settings.enabled,
                  onChanged: _saving
                      ? null
                      : (v) => _save(
                            settings.copyWith(enabled: v),
                            v ? 'Nota de venta encendida.' : 'Nota de venta apagada.',
                          ),
                )
              else if (!_loadFailed)
                Padding(
                  padding: EdgeInsets.all(dpi.space(12)),
                  child: SizedBox(
                    width: dpi.scale(18),
                    height: dpi.scale(18),
                    child: const CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
            ],
          ),
          if (_loadFailed) ...[
            SizedBox(height: dpi.space(10)),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'No se pudo leer el ajuste.',
                    style: TextStyle(fontSize: dpi.font(12), color: MangoThemeFactory.danger),
                  ),
                ),
                TextButton(onPressed: _load, child: const Text('Reintentar')),
              ],
            ),
          ],
          if (settings != null && settings.enabled) ...[
            SizedBox(height: dpi.space(14)),
            Text(
              'Prefijo de la numeración',
              style: TextStyle(fontSize: dpi.font(13), fontWeight: FontWeight.w700),
            ),
            SizedBox(height: dpi.space(2)),
            Text(
              'Se imprime como ${settings.prefix}000123. Cambiarlo no reinicia la numeración.',
              style: TextStyle(fontSize: dpi.font(11), color: muted, height: 1.35),
            ),
            SizedBox(height: dpi.space(10)),
            TextField(
              controller: _prefix,
              enabled: !_saving,
              maxLength: SalesNoteSettings.maxPrefixLength,
              textCapitalization: TextCapitalization.characters,
              inputFormatters: [FilteringTextInputFormatter.deny(RegExp(r'\s'))],
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _savePrefix(),
              decoration: InputDecoration(
                labelText: 'Prefijo',
                isDense: true,
                counterText: '',
                suffixIcon: IconButton(
                  tooltip: 'Guardar prefijo',
                  icon: const Icon(Icons.check_rounded),
                  onPressed: _saving ? null : _savePrefix,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
