import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/di/providers.dart';
import '../../../core/formatters/mango_formatters.dart';
import '../../../core/responsive/dpi_scale.dart';
import '../../../domain/inventory/inventory_models.dart';
import '../../../domain/purchasing/purchase_order.dart';
import '../../auth/viewmodel/auth_gate_view_model.dart';
import '../../theme/theme_data_factory.dart';
import '../../widgets/soft_item_picker_sheet.dart';
import '../viewmodel/purchase_orders_view_model.dart';
import 'reception_scanner_page.dart';

/// Formulario de nueva orden de compra: suplidor, bodega destino, fecha
/// esperada y líneas tomadas del inventario (cantidad y costo en unidad base,
/// como el POS). Se guarda como borrador o directamente como enviada.
class PurchaseOrderFormView extends ConsumerStatefulWidget {
  const PurchaseOrderFormView({
    super.key,
    this.initialLines = const [],
    this.initialSupplierId,
  });

  /// Líneas precargadas (p.ej. "Agregar a orden de compra" desde la ficha de
  /// un artículo o desde Qué comprar hoy).
  final List<PurchaseOrderLineDraft> initialLines;

  /// Suplidor preseleccionado (p.ej. el sugerido por la última compra).
  final String? initialSupplierId;

  @override
  ConsumerState<PurchaseOrderFormView> createState() =>
      _PurchaseOrderFormViewState();
}

class _PurchaseOrderFormViewState extends ConsumerState<PurchaseOrderFormView> {
  final _notes = TextEditingController();

  String? _supplierId;
  String? _warehouseId;
  late DateTime _expectedDate;
  final List<PurchaseOrderLineDraft> _lines = [];

  List<InventoryItemSnapshot> _inventory = const [];
  Map<String, String> _codeToItem = const {};
  bool _inventoryLoading = true;

  @override
  void initState() {
    super.initState();
    _expectedDate = DateTime.now().add(const Duration(days: 3));
    _lines.addAll(widget.initialLines);
    _supplierId = widget.initialSupplierId;
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadInventory());
  }

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  String? get _businessId =>
      ref.read(authGateViewModelProvider).profile?.businessId;

  Future<void> _loadInventory() async {
    final businessId = _businessId;
    if (businessId == null) return;
    // Si se llegó directo (ficha / Qué comprar hoy) sin pasar por Compras,
    // los suplidores y bodegas del provider aún no están cargados.
    final vm = ref.read(purchaseOrdersViewModelProvider);
    if (vm.suppliers.isEmpty || vm.warehouses.isEmpty) {
      await ref.read(purchaseOrdersViewModelProvider.notifier).load(businessId);
    }
    try {
      final items =
          await ref.read(inventoryDataServiceProvider).loadInventory(businessId);
      if (mounted) {
        setState(() {
          _inventory = items;
          _inventoryLoading = false;
        });
      }
      // Códigos de barra/SKU → escaneo directo de líneas.
      try {
        final codes = await ref
            .read(purchasingDataServiceProvider)
            .loadItemCodes(items.map((i) => i.itemId).toList(growable: false));
        if (mounted) setState(() => _codeToItem = codes);
      } catch (_) {/* escáner deshabilitado */}
    } catch (_) {
      if (mounted) setState(() => _inventoryLoading = false);
    }
  }

  /// Cada escaneo suma 1 a la línea del insumo (o la crea con cantidad 1 y
  /// costo maestro prellenado) — mismo flujo que la recepción directa.
  ScanFeedback? _handleScan(String code) {
    final itemId = _codeToItem[code];
    if (itemId == null) {
      return const ScanFeedback(
          matched: false, message: 'Código no registrado en inventario');
    }
    final item = _inventory.where((i) => i.itemId == itemId).firstOrNull;
    if (item == null) {
      return const ScanFeedback(matched: false, message: 'Insumo no encontrado');
    }
    final existing = _lines
        .where((l) => l.inventoryItemId == itemId)
        .firstOrNull;
    final double qty;
    if (existing != null) {
      qty = existing.quantity + 1;
      _lines[_lines.indexOf(existing)] = PurchaseOrderLineDraft(
        inventoryItemId: existing.inventoryItemId,
        description: existing.description,
        quantity: qty,
        unitCost: existing.unitCost,
        taxRate: existing.taxRate,
        unit: existing.unit,
      );
    } else {
      qty = 1;
      _lines.add(PurchaseOrderLineDraft(
        inventoryItemId: item.itemId,
        description: item.name,
        quantity: 1,
        unitCost: item.cost ?? 0,
        taxRate: 18,
        unit: item.unit,
      ));
    }
    setState(() {});
    return ScanFeedback(
      matched: true,
      message:
          '${item.name} · ${MangoFormatters.number(qty)} ${item.unit}',
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

  void _snack(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  double get _subtotal => _lines.fold(0.0, (sum, l) => sum + l.total);
  double get _tax => _lines.fold(0.0, (sum, l) => sum + l.taxValue);

  Future<void> _pickExpectedDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _expectedDate,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      helpText: 'Fecha esperada de entrega',
    );
    if (picked != null) setState(() => _expectedDate = picked);
  }

  Future<void> _addLine() async {
    if (_inventoryLoading) {
      _snack('Cargando inventario…');
      return;
    }
    if (_inventory.isEmpty) {
      _snack('No hay insumos en el inventario para agregar.');
      return;
    }
    final item = await showSoftItemPicker(
      context: context,
      items: _inventory,
      subtitleOf: (i) => [
        if (i.sku != null && i.sku!.isNotEmpty) i.sku!,
        'Stock: ${MangoFormatters.number(i.totalQuantity)} ${i.unit}',
        if (i.cost != null) 'Costo: ${MangoFormatters.currency(i.cost!)}',
      ].join(' · '),
    );
    if (item == null || !mounted) return;

    final draft = await showDialog<PurchaseOrderLineDraft>(
      context: context,
      builder: (_) => _LineEditorDialog(item: item),
    );
    if (draft == null || !mounted) return;
    setState(() => _lines.add(draft));
  }

  Future<void> _save(String status) async {
    final businessId = _businessId;
    if (businessId == null) return;
    if (_supplierId == null) {
      _snack('Selecciona el suplidor.');
      return;
    }
    if (_warehouseId == null) {
      _snack('Selecciona la bodega destino.');
      return;
    }
    if (_lines.isEmpty) {
      _snack('Agrega al menos una línea a la orden.');
      return;
    }

    final id = await ref.read(purchaseOrdersViewModelProvider.notifier).create(
          businessId,
          supplierId: _supplierId!,
          warehouseId: _warehouseId!,
          status: status,
          expectedDate: _expectedDate,
          notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
          lines: _lines,
        );
    if (!mounted) return;
    if (id != null) {
      Navigator.of(context).pop();
    } else {
      final err = ref.read(purchaseOrdersViewModelProvider).error;
      _snack(err ?? 'No se pudo crear la orden.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final dpi = DpiScale.of(context);
    final vm = ref.watch(purchaseOrdersViewModelProvider);

    // Preselecciona la bodega principal cuando cargan las bodegas.
    if (_warehouseId == null && vm.warehouses.isNotEmpty) {
      _warehouseId = vm.warehouses.first.id;
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Nueva orden de compra')),
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
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Subtotal ${MangoFormatters.currency(_subtotal)} · ITBIS ${MangoFormatters.currency(_tax)}',
                    style: TextStyle(
                      fontSize: dpi.font(11),
                      color: MangoThemeFactory.mutedText(context),
                    ),
                  ),
                  Text(
                    MangoFormatters.currency(_subtotal + _tax),
                    style: TextStyle(
                        fontSize: dpi.font(16), fontWeight: FontWeight.w800),
                  ),
                ],
              ),
              SizedBox(height: dpi.space(10)),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: vm.saving ? null : () => _save('draft'),
                      style: OutlinedButton.styleFrom(
                        padding:
                            EdgeInsets.symmetric(vertical: dpi.space(13)),
                      ),
                      child: const Text('Borrador'),
                    ),
                  ),
                  SizedBox(width: dpi.space(10)),
                  Expanded(
                    flex: 2,
                    child: FilledButton(
                      onPressed: vm.saving ? null : () => _save('sent'),
                      style: FilledButton.styleFrom(
                        backgroundColor: MangoThemeFactory.mango,
                        padding:
                            EdgeInsets.symmetric(vertical: dpi.space(13)),
                      ),
                      child: vm.saving
                          ? SizedBox(
                              width: dpi.icon(18),
                              height: dpi.icon(18),
                              child: const CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white),
                            )
                          : const Text('Crear y enviar'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      body: ListView(
        padding: EdgeInsets.all(dpi.space(16)),
        children: [
          DropdownButtonFormField<String>(
            initialValue: vm.suppliers.any((s) => s.id == _supplierId)
                ? _supplierId
                : null,
            decoration: const InputDecoration(labelText: 'Suplidor'),
            items: [
              for (final s in vm.suppliers)
                DropdownMenuItem(value: s.id, child: Text(s.name)),
            ],
            onChanged: (v) => setState(() => _supplierId = v),
          ),
          SizedBox(height: dpi.space(14)),
          DropdownButtonFormField<String>(
            initialValue: _warehouseId,
            decoration: const InputDecoration(labelText: 'Bodega destino'),
            items: [
              for (final w in vm.warehouses)
                DropdownMenuItem(
                    value: w.id,
                    child: Text(w.isMain ? '${w.name} (principal)' : w.name)),
            ],
            onChanged: (v) => setState(() => _warehouseId = v),
          ),
          SizedBox(height: dpi.space(14)),
          InkWell(
            onTap: _pickExpectedDate,
            child: InputDecorator(
              decoration: const InputDecoration(
                labelText: 'Fecha esperada',
                suffixIcon: Icon(Icons.calendar_today_rounded, size: 18),
              ),
              child: Text(
                  '${_expectedDate.day}/${_expectedDate.month}/${_expectedDate.year}'),
            ),
          ),
          SizedBox(height: dpi.space(14)),
          TextField(
            controller: _notes,
            maxLines: 2,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Notas (opcional)'),
          ),
          SizedBox(height: dpi.space(20)),

          Row(
            children: [
              Expanded(
                child: Text(
                  'LÍNEAS (${_lines.length})',
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
                onPressed: _addLine,
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('Agregar'),
              ),
            ],
          ),
          if (_lines.isEmpty)
            Padding(
              padding: EdgeInsets.symmetric(vertical: dpi.space(16)),
              child: Text(
                'Sin líneas todavía. Agrega insumos del inventario.',
                style: TextStyle(
                  fontSize: dpi.font(12),
                  color: MangoThemeFactory.mutedText(context),
                ),
              ),
            )
          else
            ...List.generate(_lines.length, (index) {
              final l = _lines[index];
              return Container(
                margin: EdgeInsets.only(bottom: dpi.space(8)),
                padding: EdgeInsets.all(dpi.space(12)),
                decoration: BoxDecoration(
                  color: MangoThemeFactory.cardColor(context),
                  borderRadius: BorderRadius.circular(dpi.radius(12)),
                  border:
                      Border.all(color: MangoThemeFactory.borderColor(context)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            l.description,
                            style: TextStyle(
                              fontSize: dpi.font(13),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          SizedBox(height: dpi.space(2)),
                          Text(
                            '${MangoFormatters.number(l.quantity)} ${l.unit ?? ''} × ${MangoFormatters.currency(l.unitCost)}'
                            '${l.taxRate > 0 ? ' · ITBIS ${l.taxRate.toStringAsFixed(0)}%' : ''}',
                            style: TextStyle(
                              fontSize: dpi.font(11),
                              color: MangoThemeFactory.mutedText(context),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      MangoFormatters.currency(l.total),
                      style: TextStyle(
                          fontSize: dpi.font(13), fontWeight: FontWeight.w700),
                    ),
                    IconButton(
                      icon: Icon(Icons.close_rounded,
                          size: dpi.icon(18),
                          color: MangoThemeFactory.mutedText(context)),
                      onPressed: () => setState(() => _lines.removeAt(index)),
                    ),
                  ],
                ),
              );
            }),

          SizedBox(height: dpi.space(24)),
        ],
      ),
    );
  }
}

/// Cantidad, costo unitario e ITBIS de la línea.
class _LineEditorDialog extends StatefulWidget {
  const _LineEditorDialog({required this.item});

  final InventoryItemSnapshot item;

  @override
  State<_LineEditorDialog> createState() => _LineEditorDialogState();
}

class _LineEditorDialogState extends State<_LineEditorDialog> {
  late final TextEditingController _qty;
  late final TextEditingController _cost;
  bool _applyTax = true;

  @override
  void initState() {
    super.initState();
    final suggested = widget.item.suggestedPurchase;
    _qty = TextEditingController(
        text: suggested > 0 ? suggested.toStringAsFixed(0) : '');
    _cost = TextEditingController(
        text: widget.item.cost != null ? widget.item.cost!.toString() : '');
  }

  @override
  void dispose() {
    _qty.dispose();
    _cost.dispose();
    super.dispose();
  }

  double? _parse(String text) =>
      double.tryParse(text.trim().replaceAll(',', '.'));

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.item.name),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _qty,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: 'Cantidad (${widget.item.unit})',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _cost,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: 'Costo unitario (RD\$ por ${widget.item.unit})',
            ),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Aplicar ITBIS (18%)'),
            value: _applyTax,
            onChanged: (v) => setState(() => _applyTax = v),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () {
            final qty = _parse(_qty.text);
            final cost = _parse(_cost.text);
            if (qty == null || qty <= 0) return;
            if (cost == null || cost < 0) return;
            Navigator.of(context).pop(PurchaseOrderLineDraft(
              inventoryItemId: widget.item.itemId,
              description: widget.item.name,
              quantity: qty,
              unitCost: cost,
              taxRate: _applyTax ? 18 : 0,
              unit: widget.item.unit,
            ));
          },
          child: const Text('Agregar'),
        ),
      ],
    );
  }
}
