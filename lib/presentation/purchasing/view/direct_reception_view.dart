import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../app/di/providers.dart';
import '../../../core/formatters/mango_formatters.dart';
import '../../../core/responsive/dpi_scale.dart';
import '../../../domain/inventory/inventory_models.dart';
import '../../../domain/purchasing/supplier.dart';
import '../../auth/viewmodel/auth_gate_view_model.dart';
import '../../theme/theme_data_factory.dart';
import '../../widgets/soft_item_picker_sheet.dart';
import 'reception_scanner_page.dart';

/// "Recibir stock" sin orden de compra (estilo Square): escanea o busca
/// insumos, cada escaneo suma 1, captura el costo real y registra todo vía
/// `fn_receive_purchase_order_v2` (recepción libre, idempotente).
class DirectReceptionView extends ConsumerStatefulWidget {
  const DirectReceptionView({super.key});

  @override
  ConsumerState<DirectReceptionView> createState() =>
      _DirectReceptionViewState();
}

class _DirectLine {
  _DirectLine(this.item)
      : qty = TextEditingController(text: '1'),
        cost = TextEditingController(
            text: item.cost != null && item.cost! > 0
                ? _trim(item.cost!)
                : '');

  final InventoryItemSnapshot item;
  final TextEditingController qty;
  final TextEditingController cost;

  double get qtyValue =>
      double.tryParse(qty.text.trim().replaceAll(',', '.')) ?? 0;
  double get costValue =>
      double.tryParse(cost.text.trim().replaceAll(',', '.')) ?? 0;

  static String _trim(double v) =>
      v.truncateToDouble() == v ? v.toInt().toString() : v.toString();

  void dispose() {
    qty.dispose();
    cost.dispose();
  }
}

class _DirectReceptionViewState extends ConsumerState<DirectReceptionView> {
  static const _prefsKey = 'direct_reception_key';

  final _ncf = TextEditingController();
  final _itbis = TextEditingController();
  final List<_DirectLine> _lines = [];

  List<InventoryItemSnapshot> _inventory = const [];
  List<Supplier> _suppliers = const [];
  List<WarehouseInfo> _warehouses = const [];
  Map<String, String> _codeToItem = const {};
  bool _loading = true;
  bool _saving = false;
  bool _fiscalOpen = false;
  String? _warehouseId;
  String? _supplierId;
  String? _ncfType = 'B01';
  String? _idempotencyKey;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _init());
  }

  Future<void> _init() async {
    final businessId = ref.read(authGateViewModelProvider).profile?.businessId;
    if (businessId == null) return;
    try {
      final service = ref.read(purchasingDataServiceProvider);
      final results = await Future.wait([
        ref.read(inventoryDataServiceProvider).loadInventory(businessId),
        service.loadSuppliers(businessId),
        service.loadWarehouses(businessId),
      ]);
      final inventory = results[0] as List<InventoryItemSnapshot>;
      final codes = await service
          .loadItemCodes(inventory.map((i) => i.itemId).toList(growable: false));
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getString(_prefsKey);
      final key = (stored != null && stored.isNotEmpty) ? stored : _newKey();
      if (stored == null || stored.isEmpty) {
        await prefs.setString(_prefsKey, key);
      }
      if (!mounted) return;
      setState(() {
        _inventory = inventory;
        _suppliers = (results[1] as List<Supplier>)
            .where((s) => s.isActive)
            .toList(growable: false);
        _warehouses = results[2] as List<WarehouseInfo>;
        _warehouseId =
            _warehouses.isNotEmpty ? _warehouses.first.id : null;
        _codeToItem = codes;
        _idempotencyKey = key;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
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
    for (final l in _lines) {
      l.dispose();
    }
    _ncf.dispose();
    _itbis.dispose();
    super.dispose();
  }

  void _snack(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  double get _total =>
      _lines.fold(0.0, (sum, l) => sum + l.qtyValue * l.costValue);

  /// Cada escaneo suma 1 al insumo; si aún no está en la lista, lo agrega
  /// con cantidad 1 y el costo maestro prellenado.
  ScanFeedback? _handleScan(String code) {
    final itemId = _codeToItem[code];
    if (itemId == null) {
      return const ScanFeedback(
          matched: false, message: 'Código no registrado en inventario');
    }
    final item = _inventory.where((i) => i.itemId == itemId).firstOrNull;
    if (item == null) {
      return const ScanFeedback(
          matched: false, message: 'Insumo no encontrado');
    }
    final existing =
        _lines.where((l) => l.item.itemId == itemId).firstOrNull;
    final _DirectLine line;
    if (existing != null) {
      existing.qty.text = _DirectLine._trim(existing.qtyValue + 1);
      line = existing;
    } else {
      line = _DirectLine(item); // arranca en 1
      _lines.add(line);
    }
    setState(() {});
    return ScanFeedback(
      matched: true,
      message:
          '${item.name} · ${MangoFormatters.number(line.qtyValue)} ${item.unit}',
    );
  }

  Future<void> _openScanner() async {
    if (_codeToItem.isEmpty) {
      _snack('Ningún insumo tiene código de barras ni SKU registrado.');
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ReceptionScannerPage(onCode: _handleScan),
      ),
    );
    if (mounted) setState(() {});
  }

  Future<void> _addBySearch() async {
    final item = await showSoftItemPicker(
      context: context,
      items: _inventory,
      subtitleOf: (i) => [
        if (i.sku != null && i.sku!.isNotEmpty) i.sku!,
        'Stock: ${MangoFormatters.number(i.totalQuantity)} ${i.unit}',
      ].join(' · '),
    );
    if (item == null || !mounted) return;
    final existing =
        _lines.where((l) => l.item.itemId == item.itemId).firstOrNull;
    if (existing != null) {
      existing.qty.text = _DirectLine._trim(existing.qtyValue + 1);
    } else {
      _lines.add(_DirectLine(item));
    }
    setState(() {});
  }

  Future<void> _submit() async {
    final key = _idempotencyKey;
    final warehouseId = _warehouseId;
    if (key == null || warehouseId == null) {
      _snack('Preparando la recepción, intenta de nuevo.');
      return;
    }
    final lines = <Map<String, dynamic>>[
      for (final l in _lines)
        if (l.qtyValue > 0)
          {
            'item_id': l.item.itemId,
            'qty': l.qtyValue,
            'actual_unit_cost': l.costValue,
          },
    ];
    if (lines.isEmpty) {
      _snack('Agrega al menos un insumo.');
      return;
    }
    for (final l in _lines) {
      if (l.qtyValue > 0 && l.costValue <= 0) {
        _snack('Ponle costo a "${l.item.name}".');
        return;
      }
    }

    final ncf = _ncf.text.trim();
    final itbis = double.tryParse(_itbis.text.trim().replaceAll(',', '.'));
    final fiscal = <String, dynamic>{
      if (ncf.isNotEmpty) 'ncf': ncf,
      if (ncf.isNotEmpty && _ncfType != null) 'ncf_type': _ncfType,
      'document_date': DateTime.now().toIso8601String().split('T').first,
      'itbis_invoiced': ?itbis,
      'goods_amount': _total,
    };

    setState(() => _saving = true);
    try {
      final result =
          await ref.read(purchasingDataServiceProvider).receivePurchaseOrder(
                warehouseId: warehouseId,
                lines: lines,
                idempotencyKey: key,
                supplierId: _supplierId,
                fiscal: fiscal,
                closeMode: 'complete',
                notes: 'Recepción directa desde el dashboard',
              );
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_prefsKey);
      if (!mounted) return;
      final replayed = result['replayed'] == true;
      _snack(replayed
          ? 'Esta recepción ya estaba registrada (reintento seguro).'
          : 'Stock recibido: ${result['movements_created']} movimiento(s).');
      Navigator.of(context).pop(true);
    } catch (_) {
      if (!mounted) return;
      _snack('No se pudo registrar la recepción. Intenta de nuevo.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dpi = DpiScale.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Recibir stock'),
        centerTitle: false,
        actions: [
          IconButton(
            tooltip: 'Escanear con cámara',
            icon: const Icon(Icons.qr_code_scanner_rounded),
            onPressed: _loading ? null : _openScanner,
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Container(
          padding: EdgeInsets.fromLTRB(
              dpi.space(16), dpi.space(10), dpi.space(16), dpi.space(12)),
          decoration: BoxDecoration(
            color: MangoThemeFactory.cardColor(context),
            border: Border(
              top: BorderSide(color: MangoThemeFactory.borderColor(context)),
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
                            color: MangoThemeFactory.mutedText(context))),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        MangoFormatters.currency(_total),
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
                onPressed: _saving || _loading ? null : _submit,
                style: FilledButton.styleFrom(
                  backgroundColor: MangoThemeFactory.mango,
                  padding: EdgeInsets.symmetric(
                      horizontal: dpi.space(20), vertical: dpi.space(14)),
                ),
                icon: _saving
                    ? SizedBox(
                        width: dpi.icon(16),
                        height: dpi.icon(16),
                        child: const CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.check_circle_rounded),
                label: Text(_saving ? 'Registrando…' : 'Registrar'),
              ),
            ],
          ),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: EdgeInsets.all(dpi.space(16)),
              children: [
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: _warehouseId,
                        decoration:
                            const InputDecoration(labelText: 'Bodega'),
                        items: [
                          for (final w in _warehouses)
                            DropdownMenuItem(
                                value: w.id,
                                child: Text(w.isMain
                                    ? '${w.name} (principal)'
                                    : w.name)),
                        ],
                        onChanged: (v) => setState(() => _warehouseId = v),
                      ),
                    ),
                    SizedBox(width: dpi.space(10)),
                    Expanded(
                      child: DropdownButtonFormField<String?>(
                        initialValue: _supplierId,
                        decoration: const InputDecoration(
                            labelText: 'Suplidor (opcional)'),
                        items: [
                          const DropdownMenuItem<String?>(
                              value: null, child: Text('Sin suplidor')),
                          for (final s in _suppliers)
                            DropdownMenuItem<String?>(
                                value: s.id, child: Text(s.name)),
                        ],
                        onChanged: (v) => setState(() => _supplierId = v),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: dpi.space(16)),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'INSUMOS (${_lines.length})',
                        style: TextStyle(
                          fontSize: dpi.font(10),
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.6,
                          color: MangoThemeFactory.mutedText(context),
                        ),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: _openScanner,
                      icon: const Icon(Icons.qr_code_scanner_rounded, size: 16),
                      label: const Text('Escanear'),
                    ),
                    TextButton.icon(
                      onPressed: _addBySearch,
                      icon: const Icon(Icons.add_rounded, size: 18),
                      label: const Text('Buscar'),
                    ),
                  ],
                ),
                if (_lines.isEmpty)
                  Container(
                    padding: EdgeInsets.all(dpi.space(24)),
                    alignment: Alignment.center,
                    child: Column(
                      children: [
                        Icon(Icons.qr_code_scanner_rounded,
                            size: dpi.icon(40),
                            color: MangoThemeFactory.mutedText(context)
                                .withValues(alpha: 0.5)),
                        SizedBox(height: dpi.space(8)),
                        Text(
                          'Escanea los productos que llegaron\no búscalos por nombre.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              color: MangoThemeFactory.mutedText(context)),
                        ),
                      ],
                    ),
                  )
                else
                  ...List.generate(_lines.length, (index) {
                    final l = _lines[index];
                    return Container(
                      margin: EdgeInsets.only(bottom: dpi.space(10)),
                      padding: EdgeInsets.all(dpi.space(12)),
                      decoration: BoxDecoration(
                        color: MangoThemeFactory.cardColor(context),
                        borderRadius: BorderRadius.circular(dpi.radius(14)),
                        border: Border.all(
                            color: MangoThemeFactory.borderColor(context)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  l.item.name,
                                  style: TextStyle(
                                      fontSize: dpi.font(13.5),
                                      fontWeight: FontWeight.w700),
                                ),
                              ),
                              IconButton(
                                visualDensity: VisualDensity.compact,
                                icon: Icon(Icons.close_rounded,
                                    size: dpi.icon(18),
                                    color:
                                        MangoThemeFactory.mutedText(context)),
                                onPressed: () => setState(
                                    () => _lines.removeAt(index).dispose()),
                              ),
                            ],
                          ),
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: l.qty,
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                          decimal: true),
                                  onChanged: (_) => setState(() {}),
                                  decoration: InputDecoration(
                                    labelText: 'Cantidad (${l.item.unit})',
                                    isDense: true,
                                  ),
                                ),
                              ),
                              SizedBox(width: dpi.space(10)),
                              Expanded(
                                child: TextField(
                                  controller: l.cost,
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                          decimal: true),
                                  onChanged: (_) => setState(() {}),
                                  decoration: const InputDecoration(
                                    labelText: 'Costo unitario',
                                    prefixText: 'RD\$ ',
                                    isDense: true,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  }),
                SizedBox(height: dpi.space(8)),

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
                          'DATOS FISCALES (606) · opcional',
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
                          decoration:
                              const InputDecoration(labelText: 'Tipo'),
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
                  TextField(
                    controller: _itbis,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'ITBIS facturado',
                      prefixText: 'RD\$ ',
                    ),
                  ),
                ],
                SizedBox(height: dpi.space(24)),
              ],
            ),
    );
  }
}
