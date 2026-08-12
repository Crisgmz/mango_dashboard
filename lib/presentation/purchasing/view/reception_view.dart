import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../app/di/providers.dart';
import '../../../core/auth/role_mapper.dart';
import '../../../core/formatters/mango_formatters.dart';
import '../../../core/responsive/dpi_scale.dart';
import '../../../domain/purchasing/purchase_order.dart';
import '../../auth/viewmodel/auth_gate_view_model.dart';
import '../../theme/theme_data_factory.dart';
import 'reception_scanner_page.dart';

/// Pantalla de recepción de mercancía (PRD 6.1 F4): por cada línea pendiente
/// captura cantidad recibida y costo REAL facturado, con semáforo
/// verde/ámbar/rojo, bloque fiscal para el 606 y cierre parcial/corto.
/// Envía todo por `fn_receive_purchase_order_v2` con clave de idempotencia
/// que sobrevive al cierre de la app (SharedPreferences).
class ReceptionView extends ConsumerStatefulWidget {
  const ReceptionView({super.key, required this.order});

  /// La OC con sus líneas (cargada por el detalle).
  final PurchaseOrder order;

  @override
  ConsumerState<ReceptionView> createState() => _ReceptionViewState();
}

class _LineInput {
  _LineInput(this.line)
      : qty = TextEditingController(
            text: _trim(max(line.quantityOrdered - line.quantityReceived, 0))),
        cost = TextEditingController(text: _trim(line.unitCost));

  final PurchaseOrderLine line;
  final TextEditingController qty;
  final TextEditingController cost;

  double get pending =>
      max(line.quantityOrdered - line.quantityReceived, 0);

  double get qtyValue =>
      double.tryParse(qty.text.trim().replaceAll(',', '.')) ?? 0;

  double get costValue =>
      double.tryParse(cost.text.trim().replaceAll(',', '.')) ?? 0;

  /// Variación % del costo real vs. el de la OC (null si la OC no trae costo).
  double? get variancePct {
    if (line.unitCost <= 0) return null;
    return (costValue - line.unitCost) / line.unitCost * 100;
  }

  static String _trim(double v) =>
      v.truncateToDouble() == v ? v.toInt().toString() : v.toString();

  void dispose() {
    qty.dispose();
    cost.dispose();
  }
}

class _ReceptionViewState extends ConsumerState<ReceptionView> {
  late final List<_LineInput> _inputs;
  final _ncf = TextEditingController();
  final _itbis = TextEditingController();
  bool _fiscalOpen = false;
  String? _ncfType = 'B01';
  String? _paymentMethod;
  DateTime _documentDate = DateTime.now();
  bool _shortClose = false;
  bool _saving = false;
  double _threshold = 3;
  String? _idempotencyKey;

  /// Código de barras / SKU → item_id, para el escaneo con cámara.
  Map<String, String> _codeToItem = const {};

  String get _draftKey => 'reception_key_${widget.order.id}';

  @override
  void initState() {
    super.initState();
    _inputs = [
      for (final l in widget.order.lines)
        if (l.quantityOrdered > l.quantityReceived) _LineInput(l),
    ];
    WidgetsBinding.instance.addPostFrameCallback((_) => _init());
  }

  Future<void> _init() async {
    final businessId = ref.read(authGateViewModelProvider).profile?.businessId;
    if (businessId != null) {
      final t = await ref
          .read(purchasingDataServiceProvider)
          .loadCostVarianceThreshold(businessId);
      if (mounted) setState(() => _threshold = t);
    }
    // Códigos de barra/SKU de los insumos de la orden, para el escáner.
    final itemIds = <String>[
      for (final i in _inputs)
        if (i.line.inventoryItemId != null) i.line.inventoryItemId!,
    ];
    if (itemIds.isNotEmpty) {
      try {
        final codes = await ref
            .read(purchasingDataServiceProvider)
            .loadItemCodes(itemIds);
        if (mounted) setState(() => _codeToItem = codes);
      } catch (_) {/* sin códigos: el escáner avisará que no hay mapeo */}
    }
    // La clave se genera al INICIAR la recepción y se persiste: si la app se
    // cierra a mitad, el reintento reutiliza la misma clave y nunca duplica.
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_draftKey);
    if (stored != null && stored.isNotEmpty) {
      _idempotencyKey = stored;
    } else {
      _idempotencyKey = _newKey();
      await prefs.setString(_draftKey, _idempotencyKey!);
    }
  }

  static String _newKey() {
    final rnd = Random.secure();
    String hex(int n) =>
        List.generate(n, (_) => rnd.nextInt(16).toRadixString(16)).join();
    return '${hex(8)}-${hex(4)}-4${hex(3)}-${hex(4)}-${hex(12)}';
  }

  @override
  void dispose() {
    for (final i in _inputs) {
      i.dispose();
    }
    _ncf.dispose();
    _itbis.dispose();
    super.dispose();
  }

  void _snack(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  /// Semáforo de la línea: verde = completa y costo dentro del umbral;
  /// ámbar = cantidad distinta a la pendiente; rojo = variación sobre umbral.
  Color _lineColor(_LineInput i) {
    final v = i.variancePct;
    if (v != null && v.abs() > _threshold) return MangoThemeFactory.danger;
    if (i.qtyValue != i.pending) return MangoThemeFactory.warning;
    return MangoThemeFactory.success;
  }

  bool get _hasShort => _inputs.any((i) => i.qtyValue < i.pending);
  int get _overThresholdCount => _inputs
      .where((i) => i.qtyValue > 0 && (i.variancePct?.abs() ?? 0) > _threshold)
      .length;

  double get _receivedTotal =>
      _inputs.fold(0.0, (sum, i) => sum + i.qtyValue * i.costValue);

  Future<void> _pickDocumentDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _documentDate,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now(),
      helpText: 'Fecha del documento fiscal',
    );
    if (picked != null) setState(() => _documentDate = picked);
  }

  Future<void> _submit() async {
    final key = _idempotencyKey;
    if (key == null) {
      _snack('Preparando la recepción, intenta de nuevo.');
      return;
    }
    final lines = <Map<String, dynamic>>[
      for (final i in _inputs)
        if (i.qtyValue > 0)
          {
            'poi_id': i.line.id,
            'qty': i.qtyValue,
            'actual_unit_cost': i.costValue,
          },
    ];
    if (lines.isEmpty) {
      _snack('Indica al menos una cantidad recibida.');
      return;
    }
    for (final i in _inputs) {
      if (i.qtyValue > 0 && i.costValue <= 0) {
        _snack('El costo de "${i.line.description}" no puede ser 0.');
        return;
      }
    }

    final closeMode = !_hasShort
        ? 'complete'
        : (_shortClose ? 'short_closed' : 'partial');

    final ncf = _ncf.text.trim();
    final itbis = double.tryParse(_itbis.text.trim().replaceAll(',', '.'));
    final fiscal = <String, dynamic>{
      if (ncf.isNotEmpty) 'ncf': ncf,
      if (ncf.isNotEmpty && _ncfType != null) 'ncf_type': _ncfType,
      'document_date':
          _documentDate.toIso8601String().split('T').first,
      'itbis_invoiced': ?itbis,
      'goods_amount': _receivedTotal,
      'payment_method': ?_paymentMethod,
    };

    setState(() => _saving = true);
    try {
      final result =
          await ref.read(purchasingDataServiceProvider).receivePurchaseOrder(
                warehouseId: widget.order.warehouseId ?? '',
                lines: lines,
                idempotencyKey: key,
                orderId: widget.order.id,
                supplierId: widget.order.supplierId,
                fiscal: fiscal,
                closeMode: closeMode,
              );
      // Éxito: la clave ya cumplió su ciclo — la próxima recepción usa otra.
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_draftKey);
      if (!mounted) return;
      final replayed = result['replayed'] == true;
      final movements = result['movements_created'] ?? 0;
      final poStatus = result['po_status']?.toString();
      _snack(replayed
          ? 'Esta recepción ya estaba registrada (reintento seguro).'
          : 'Recepción registrada: $movements movimiento(s)'
              '${poStatus != null ? ' · orden $poStatus' : ''}.');
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      final msg = e.toString();
      if (msg.contains('COST_VARIANCE_UNAPPROVED')) {
        _snack('Hay variaciones de costo sobre el umbral ($_threshold%). '
            'Necesitas que un admin apruebe esta recepción.');
      } else if (msg.contains('PURCHASE_ORDER_ALREADY_RECEIVED')) {
        _snack('La orden ya fue recibida por completo.');
      } else {
        _snack('No se pudo registrar la recepción. Intenta de nuevo.');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dpi = DpiScale.of(context);
    final canApprove = isOwnerOrAdminRole(
        ref.read(authGateViewModelProvider).profile?.normalizedRole);

    final green = _inputs
        .where((i) => _lineColor(i) == MangoThemeFactory.success)
        .length;
    final amber = _inputs
        .where((i) => _lineColor(i) == MangoThemeFactory.warning)
        .length;
    final red = _inputs
        .where((i) => _lineColor(i) == MangoThemeFactory.danger)
        .length;

    return Scaffold(
      appBar: AppBar(
        title: Text('Recibir ${widget.order.orderNumber}'),
        centerTitle: false,
        actions: [
          if (_inputs.isNotEmpty)
            IconButton(
              tooltip: 'Escanear con cámara',
              icon: const Icon(Icons.qr_code_scanner_rounded),
              onPressed: _openScanner,
            ),
        ],
      ),
      bottomNavigationBar: _inputs.isEmpty
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
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('Total recibido',
                              style: TextStyle(
                                  fontSize: dpi.font(10.5),
                                  color:
                                      MangoThemeFactory.mutedText(context))),
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              MangoFormatters.currency(_receivedTotal),
                              style: TextStyle(
                                  fontSize: dpi.font(17),
                                  fontWeight: FontWeight.w800),
                            ),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(width: dpi.space(12)),
                    FilledButton.icon(
                      onPressed: _saving ? null : _submit,
                      style: FilledButton.styleFrom(
                        backgroundColor: MangoThemeFactory.mango,
                        padding: EdgeInsets.symmetric(
                            horizontal: dpi.space(20),
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
                      label:
                          Text(_saving ? 'Registrando…' : 'Registrar'),
                    ),
                  ],
                ),
              ),
            ),
      body: _inputs.isEmpty
          ? Center(
              child: Padding(
                padding: EdgeInsets.all(dpi.space(24)),
                child: Text(
                  'Esta orden no tiene líneas pendientes por recibir.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: MangoThemeFactory.mutedText(context)),
                ),
              ),
            )
          : ListView(
              padding: EdgeInsets.all(dpi.space(16)),
              children: [
                // ── Resumen semáforo ──
                Container(
                  padding: EdgeInsets.all(dpi.space(16)),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: [
                      MangoThemeFactory.mango,
                      MangoThemeFactory.mangoDeep,
                    ]),
                    borderRadius: BorderRadius.circular(dpi.radius(18)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.order.supplierName ?? 'Sin suplidor',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: dpi.font(15),
                          fontWeight: FontWeight.w800,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      SizedBox(height: dpi.space(2)),
                      Text(
                        '${_inputs.length} línea(s) pendientes · umbral ±${_threshold.toStringAsFixed(_threshold.truncateToDouble() == _threshold ? 0 : 1)}%',
                        style: TextStyle(
                            color: Colors.white70, fontSize: dpi.font(11)),
                      ),
                      SizedBox(height: dpi.space(12)),
                      Row(
                        children: [
                          _statusPill(dpi, Colors.white, '$green completas'),
                          SizedBox(width: dpi.space(6)),
                          _statusPill(dpi, Colors.white, '$amber ajustadas'),
                          SizedBox(width: dpi.space(6)),
                          _statusPill(dpi, Colors.white, '$red sobre umbral',
                              alert: red > 0),
                        ],
                      ),
                    ],
                  ),
                ),
                SizedBox(height: dpi.space(14)),

                ..._inputs.map((i) => _lineTile(context, dpi, i)),

                if (_overThresholdCount > 0) ...[
                  SizedBox(height: dpi.space(4)),
                  Container(
                    padding: EdgeInsets.all(dpi.space(10)),
                    decoration: BoxDecoration(
                      color: MangoThemeFactory.danger.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(dpi.radius(10)),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.warning_amber_rounded,
                            size: dpi.icon(16), color: MangoThemeFactory.danger),
                        SizedBox(width: dpi.space(8)),
                        Expanded(
                          child: Text(
                            canApprove
                                ? '$_overThresholdCount línea(s) exceden el umbral: '
                                    'quedará registrada tu aprobación en la bitácora.'
                                : '$_overThresholdCount línea(s) exceden el umbral: '
                                    'necesitas aprobación de un admin para cerrar.',
                            style: TextStyle(
                              fontSize: dpi.font(11.5),
                              color: MangoThemeFactory.danger,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                SizedBox(height: dpi.space(16)),

                // ── Bloque fiscal (606) ──
                InkWell(
                  onTap: () => setState(() => _fiscalOpen = !_fiscalOpen),
                  child: Row(
                    children: [
                      Icon(Icons.receipt_long_rounded,
                          size: dpi.icon(16),
                          color: MangoThemeFactory.mutedText(context)),
                      SizedBox(width: dpi.space(6)),
                      Expanded(
                        child: Text(
                          'DATOS FISCALES (606)${_ncf.text.trim().isNotEmpty ? ' · ${_ncf.text.trim()}' : ' · opcional'}',
                          style: TextStyle(
                            fontSize: dpi.font(10),
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.6,
                            color: MangoThemeFactory.mutedText(context),
                          ),
                        ),
                      ),
                      AnimatedRotation(
                        turns: _fiscalOpen ? 0.5 : 0,
                        duration: const Duration(milliseconds: 150),
                        child: Icon(Icons.expand_more_rounded,
                            size: dpi.icon(18),
                            color: MangoThemeFactory.mutedText(context)),
                      ),
                    ],
                  ),
                ),
                if (_fiscalOpen) ...[
                  SizedBox(height: dpi.space(10)),
                  Row(
                    children: [
                      Expanded(
                        flex: 2,
                        child: TextField(
                          controller: _ncf,
                          textCapitalization: TextCapitalization.characters,
                          onChanged: (_) => setState(() {}),
                          decoration: const InputDecoration(
                            labelText: 'NCF de la factura',
                            hintText: 'B0100000123',
                          ),
                        ),
                      ),
                      SizedBox(width: dpi.space(10)),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: _ncfType,
                          decoration: const InputDecoration(labelText: 'Tipo'),
                          items: const [
                            DropdownMenuItem(value: 'B01', child: Text('B01')),
                            DropdownMenuItem(value: 'B02', child: Text('B02')),
                            DropdownMenuItem(value: 'B11', child: Text('B11')),
                            DropdownMenuItem(value: 'B13', child: Text('B13')),
                            DropdownMenuItem(value: 'E31', child: Text('E31')),
                          ],
                          onChanged: (v) => setState(() => _ncfType = v),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: dpi.space(12)),
                  Row(
                    children: [
                      Expanded(
                        child: InkWell(
                          onTap: _pickDocumentDate,
                          child: InputDecorator(
                            decoration: const InputDecoration(
                              labelText: 'Fecha documento',
                              suffixIcon:
                                  Icon(Icons.calendar_today_rounded, size: 16),
                            ),
                            child: Text(MangoFormatters.date(_documentDate)),
                          ),
                        ),
                      ),
                      SizedBox(width: dpi.space(10)),
                      Expanded(
                        child: TextField(
                          controller: _itbis,
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          decoration: const InputDecoration(
                            labelText: 'ITBIS facturado',
                            prefixText: 'RD\$ ',
                          ),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: dpi.space(12)),
                  DropdownButtonFormField<String>(
                    initialValue: _paymentMethod,
                    decoration:
                        const InputDecoration(labelText: 'Forma de pago'),
                    items: const [
                      DropdownMenuItem(value: 'cash', child: Text('Efectivo')),
                      DropdownMenuItem(value: 'card', child: Text('Tarjeta')),
                      DropdownMenuItem(
                          value: 'transfer', child: Text('Transferencia')),
                      DropdownMenuItem(
                          value: 'credit', child: Text('Crédito (por pagar)')),
                    ],
                    onChanged: (v) => setState(() => _paymentMethod = v),
                  ),
                ],

                SizedBox(height: dpi.space(16)),
                if (_hasShort)
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Cerrar la orden con pendientes'),
                    subtitle: Text(
                      _shortClose
                          ? 'Cierre corto: lo no recibido se descarta y la orden queda recibida.'
                          : 'La orden quedará parcial y podrás recibir el resto después.',
                      style: TextStyle(
                        fontSize: dpi.font(11.5),
                        color: MangoThemeFactory.mutedText(context),
                      ),
                    ),
                    value: _shortClose,
                    activeThumbColor: MangoThemeFactory.warning,
                    onChanged: (v) => setState(() => _shortClose = v),
                  ),

                SizedBox(height: dpi.space(24)),
              ],
            ),
    );
  }

  /// Cada lectura válida suma 1 a la línea del insumo escaneado.
  ScanFeedback? _handleScan(String code) {
    final itemId = _codeToItem[code];
    if (itemId == null) {
      return const ScanFeedback(
          matched: false, message: 'Código no está en esta orden');
    }
    for (final i in _inputs) {
      if (i.line.inventoryItemId != itemId) continue;
      final next = i.qtyValue + 1;
      i.qty.text = _LineInput._trim(next);
      setState(() {});
      final over = next > i.pending ? ' · sobrante' : '';
      return ScanFeedback(
        matched: true,
        message:
            '${i.line.description} · ${MangoFormatters.number(next)} de ${MangoFormatters.number(i.pending)}$over',
      );
    }
    return const ScanFeedback(
        matched: false, message: 'El insumo no tiene línea pendiente');
  }

  Future<void> _openScanner() async {
    if (_codeToItem.isEmpty) {
      _snack('Los insumos de esta orden no tienen código de barras ni SKU '
          'registrado. Agrégalos en Inventario para poder escanear.');
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ReceptionScannerPage(onCode: _handleScan),
      ),
    );
    if (mounted) setState(() {});
  }

  Widget _quickFill(DpiScale dpi, String label, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(dpi.radius(8)),
      child: Container(
        padding: EdgeInsets.symmetric(
            horizontal: dpi.space(8), vertical: dpi.space(3)),
        decoration: BoxDecoration(
          color: MangoThemeFactory.mango.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(dpi.radius(8)),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: dpi.font(10.5),
            fontWeight: FontWeight.w800,
            color: MangoThemeFactory.mango,
          ),
        ),
      ),
    );
  }

  Widget _statusPill(DpiScale dpi, Color textColor, String label,
      {bool alert = false}) {
    return Container(
      padding: EdgeInsets.symmetric(
          horizontal: dpi.space(8), vertical: dpi.space(3)),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: alert ? 0.35 : 0.18),
        borderRadius: BorderRadius.circular(dpi.radius(999)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: dpi.font(10),
          fontWeight: FontWeight.w800,
          color: textColor,
        ),
      ),
    );
  }

  Widget _lineTile(BuildContext context, DpiScale dpi, _LineInput i) {
    final color = _lineColor(i);
    final variance = i.variancePct;
    return Container(
      margin: EdgeInsets.only(bottom: dpi.space(10)),
      padding: EdgeInsets.all(dpi.space(12)),
      decoration: BoxDecoration(
        color: MangoThemeFactory.cardColor(context),
        borderRadius: BorderRadius.circular(dpi.radius(14)),
        border: Border.all(color: color.withValues(alpha: 0.55), width: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: dpi.scale(10),
                height: dpi.scale(10),
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              SizedBox(width: dpi.space(8)),
              Expanded(
                child: Text(
                  i.line.description,
                  style: TextStyle(
                      fontSize: dpi.font(13.5), fontWeight: FontWeight.w700),
                ),
              ),
              Text(
                'Pend: ${MangoFormatters.number(i.pending)}',
                style: TextStyle(
                  fontSize: dpi.font(11),
                  color: MangoThemeFactory.mutedText(context),
                ),
              ),
              SizedBox(width: dpi.space(8)),
              _quickFill(dpi, 'Todo', () {
                i.qty.text = _LineInput._trim(i.pending);
                setState(() {});
              }),
              SizedBox(width: dpi.space(4)),
              _quickFill(dpi, '0', () {
                i.qty.text = '0';
                setState(() {});
              }),
            ],
          ),
          SizedBox(height: dpi.space(10)),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: i.qty,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    labelText: 'Recibido',
                    isDense: true,
                  ),
                ),
              ),
              SizedBox(width: dpi.space(10)),
              Expanded(
                child: TextField(
                  controller: i.cost,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    labelText: 'Costo real',
                    prefixText: 'RD\$ ',
                    isDense: true,
                    helperText: 'OC: ${MangoFormatters.currency(i.line.unitCost)}',
                  ),
                ),
              ),
            ],
          ),
          if (variance != null && variance.abs() > 0.005) ...[
            SizedBox(height: dpi.space(6)),
            Text(
              'Variación: ${variance > 0 ? '+' : ''}${variance.toStringAsFixed(1)}%'
              '${variance.abs() > _threshold ? ' — sobre el umbral' : ''}',
              style: TextStyle(
                fontSize: dpi.font(11),
                fontWeight: FontWeight.w700,
                color: variance.abs() > _threshold
                    ? MangoThemeFactory.danger
                    : MangoThemeFactory.mutedText(context),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
