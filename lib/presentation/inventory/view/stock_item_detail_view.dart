import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/di/providers.dart';
import '../../../core/formatters/mango_formatters.dart';
import '../../../core/responsive/dpi_scale.dart';
import '../../../domain/inventory/inventory_models.dart';
import '../../../domain/purchasing/purchase_order.dart';
import '../../auth/viewmodel/auth_gate_view_model.dart';
import '../../purchasing/view/purchase_order_form_view.dart';
import '../../theme/theme_data_factory.dart';

/// Pantalla C del PRD 6.2 — Ficha de artículo: tres bloques en scroll (sin
/// pestañas): economía + gestionar stock, detalles, stock por bodega con
/// cobertura, y kardex. Todo ajuste manual escribe en inventory_movements
/// con motivo obligatorio — no hay edición silenciosa de cantidad.
class StockItemDetailView extends ConsumerStatefulWidget {
  const StockItemDetailView({
    super.key,
    required this.item,
    this.price,
    this.committed = 0,
  });

  final InventoryItemSnapshot item;

  /// Precio del producto vinculado (para Precio/Margen).
  final double? price;

  /// Comprometido en órdenes abiertas del POS (Disponible = en mano − esto).
  final double committed;

  @override
  ConsumerState<StockItemDetailView> createState() =>
      _StockItemDetailViewState();
}

class _StockItemDetailViewState extends ConsumerState<StockItemDetailView> {
  late InventoryItemSnapshot _item;
  String? _barcode;
  String? _purchaseUnit;
  double _packSize = 1;
  String? _preferredSupplierId;
  String? _preferredSupplierName;
  Map<String, double> _onOrderByWh = const {};
  List<KardexEntry> _kardex = const [];
  double? _dailyRate;

  String? get _businessId =>
      ref.read(authGateViewModelProvider).profile?.businessId;

  @override
  void initState() {
    super.initState();
    _item = widget.item;
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final businessId = _businessId;
    final service = ref.read(inventoryDataServiceProvider);
    // Cargas independientes: la que falle deja su bloque sin dato.
    try {
      final extras = await service.loadItemExtras(_item.itemId);
      if (mounted) {
        setState(() {
          _barcode = extras.barcode;
          _purchaseUnit = extras.purchaseUnit;
          _packSize = extras.packSize;
          _preferredSupplierId = extras.preferredSupplierId;
          _preferredSupplierName = extras.preferredSupplierName;
        });
      }
    } catch (_) {}
    try {
      final kardex = await service.loadKardex(_item.itemId);
      if (mounted) setState(() => _kardex = kardex);
    } catch (_) {}
    try {
      final rate = await service.loadDailySaleRate28d(_item.itemId);
      if (mounted) setState(() => _dailyRate = rate);
    } catch (_) {}
    if (businessId != null) {
      try {
        final onOrder = await ref
            .read(purchasingDataServiceProvider)
            .loadItemOnOrderByWarehouse(businessId, _item.itemId);
        if (mounted) setState(() => _onOrderByWh = onOrder);
      } catch (_) {}
    }
  }

  Future<void> _reloadItem() async {
    final businessId = _businessId;
    if (businessId == null) return;
    try {
      final items = await ref
          .read(inventoryDataServiceProvider)
          .loadInventory(businessId);
      final fresh = items.where((i) => i.itemId == _item.itemId).firstOrNull;
      if (fresh != null && mounted) setState(() => _item = fresh);
    } catch (_) {}
    _load();
  }

  void _snack(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  double? get _marginPct {
    final p = widget.price;
    final c = _item.cost;
    if (p == null || p <= 0 || c == null) return null;
    return (p - c) / p * 100;
  }

  /// Días de cobertura según venta de 28 días.
  double? get _coverageDays {
    final rate = _dailyRate;
    if (rate == null || rate <= 0) return null;
    return _item.totalQuantity / rate;
  }

  // ── Acciones ──

  Future<void> _adjustStock() async {
    final businessId = _businessId;
    if (businessId == null) return;
    final result = await showDialog<
        ({String warehouseId, double counted, String reason, String? notes})>(
      context: context,
      builder: (_) => _AdjustDialog(item: _item),
    );
    if (result == null || !mounted) return;
    try {
      await ref.read(inventoryDataServiceProvider).adjustStock(
            businessId: businessId,
            warehouseId: result.warehouseId,
            itemId: _item.itemId,
            countedQuantity: result.counted,
            reasonCode: result.reason,
            notes: result.notes,
          );
      _snack('Ajuste registrado con motivo en el kardex.');
      _reloadItem();
    } catch (_) {
      _snack('No se pudo registrar el ajuste.');
    }
  }

  Future<void> _editLimits() async {
    final result = await showDialog<({double min, double? max})>(
      context: context,
      builder: (_) => _LimitsDialog(item: _item),
    );
    if (result == null || !mounted) return;
    try {
      await ref.read(inventoryDataServiceProvider).updateStockLimits(
            itemId: _item.itemId,
            minStock: result.min,
            maxStock: result.max,
          );
      _snack('Puntos de reorden actualizados.');
      _reloadItem();
    } catch (_) {
      _snack('No se pudo actualizar.');
    }
  }

  /// Elige el suplidor preferido: manda sobre la heurística de última compra
  /// en "Qué comprar hoy" (PRD 6.2 C.2).
  Future<void> _editPreferredSupplier() async {
    final businessId = _businessId;
    if (businessId == null) return;
    List suppliers;
    try {
      suppliers = (await ref
              .read(purchasingDataServiceProvider)
              .loadSuppliers(businessId))
          .where((s) => s.isActive)
          .toList();
    } catch (_) {
      _snack('No se pudieron cargar los suplidores.');
      return;
    }
    if (!mounted) return;
    if (suppliers.isEmpty) {
      _snack('Crea suplidores primero (Inventario → Suplidores).');
      return;
    }
    String? selected = _preferredSupplierId;
    final result = await showDialog<({String? id})>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Suplidor preferido'),
          content: DropdownButtonFormField<String?>(
            initialValue:
                suppliers.any((s) => (s as dynamic).id == selected)
                    ? selected
                    : null,
            decoration: const InputDecoration(labelText: 'Suplidor'),
            items: [
              const DropdownMenuItem<String?>(
                  value: null, child: Text('Sin preferido (última compra)')),
              for (final s in suppliers)
                DropdownMenuItem<String?>(
                    value: (s as dynamic).id as String,
                    child: Text((s as dynamic).name as String)),
            ],
            onChanged: (v) => setDialogState(() => selected = v),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop((id: selected)),
              child: const Text('Guardar'),
            ),
          ],
        ),
      ),
    );
    if (result == null || !mounted) return;
    try {
      await ref
          .read(inventoryDataServiceProvider)
          .setPreferredSupplier(_item.itemId, result.id);
      _snack(result.id == null
          ? 'Preferido eliminado: vuelve la heurística de última compra.'
          : 'Suplidor preferido guardado.');
      _load();
    } catch (_) {
      _snack('No se pudo guardar (¿migración de suplidor preferido aplicada?).');
    }
  }

  void _addToPurchaseOrder() {
    final suggested = _item.suggestedPurchase;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PurchaseOrderFormView(initialLines: [
          PurchaseOrderLineDraft(
            inventoryItemId: _item.itemId,
            description: _item.name,
            quantity: suggested > 0 ? suggested : 1,
            unitCost: _item.cost ?? 0,
            taxRate: 18,
            unit: _item.unit,
          ),
        ]),
      ),
    ).then((_) => _reloadItem());
  }

  @override
  Widget build(BuildContext context) {
    final dpi = DpiScale.of(context);
    final margin = _marginPct;
    final available = _item.totalQuantity - widget.committed;

    return Scaffold(
      appBar: AppBar(title: Text(_item.name), centerTitle: false),
      body: RefreshIndicator(
        onRefresh: _reloadItem,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(
              parent: BouncingScrollPhysics()),
          padding: EdgeInsets.all(dpi.space(16)),
          children: [
            // ── C.1 Economía ──
            Row(
              children: [
                _econTile(
                    context,
                    'PRECIO',
                    widget.price != null
                        ? MangoFormatters.currency(widget.price!)
                        : '—'),
                SizedBox(width: dpi.space(8)),
                _econTile(
                    context,
                    'COSTO PROM.',
                    _item.cost != null
                        ? MangoFormatters.currency(_item.cost!)
                        : '—'),
                SizedBox(width: dpi.space(8)),
                _econTile(
                  context,
                  'MARGEN',
                  margin != null ? '${margin.toStringAsFixed(0)}%' : '—',
                  valueColor: margin == null
                      ? null
                      : margin >= 30
                          ? MangoThemeFactory.success
                          : margin >= 15
                              ? MangoThemeFactory.warning
                              : MangoThemeFactory.danger,
                ),
              ],
            ),
            SizedBox(height: dpi.space(12)),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _adjustStock,
                    style: OutlinedButton.styleFrom(
                        padding:
                            EdgeInsets.symmetric(vertical: dpi.space(12))),
                    icon: Icon(Icons.tune_rounded, size: dpi.icon(16)),
                    label: const Text('Ajustar stock'),
                  ),
                ),
                SizedBox(width: dpi.space(8)),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _editLimits,
                    style: OutlinedButton.styleFrom(
                        padding:
                            EdgeInsets.symmetric(vertical: dpi.space(12))),
                    icon: Icon(Icons.speed_rounded, size: dpi.icon(16)),
                    label: const Text('Reorden'),
                  ),
                ),
              ],
            ),
            SizedBox(height: dpi.space(18)),

            // ── C.2 Detalles ──
            _sectionLabel(context, 'DETALLES DEL ARTÍCULO'),
            Container(
              padding: EdgeInsets.symmetric(
                  horizontal: dpi.space(14), vertical: dpi.space(6)),
              decoration: BoxDecoration(
                color: MangoThemeFactory.cardColor(context),
                borderRadius: BorderRadius.circular(dpi.radius(14)),
                border:
                    Border.all(color: MangoThemeFactory.borderColor(context)),
              ),
              child: Column(
                children: [
                  InkWell(
                    onTap: _editPreferredSupplier,
                    child: _detailRow(
                      context,
                      'Suplidor preferido',
                      _preferredSupplierName ?? 'Toca para elegir',
                    ),
                  ),
                  _detailRow(context, 'Unidad de venta', _item.unit),
                  _detailRow(
                      context,
                      'Unidad de compra',
                      _purchaseUnit != null && _purchaseUnit!.isNotEmpty
                          ? '$_purchaseUnit · ${MangoFormatters.number(_packSize)} ${_item.unit}'
                          : '1:1'),
                  _detailRow(context, 'SKU', _item.sku ?? '—'),
                  _detailRow(context, 'Código de barras', _barcode ?? '—',
                      monospace: true),
                  _detailRow(
                      context,
                      'Punto de reorden',
                      _item.minStock > 0
                          ? '${MangoFormatters.number(_item.minStock)} ${_item.unit}'
                          : 'Sin configurar'),
                  if (_item.maxStock != null)
                    _detailRow(context, 'Stock máximo',
                        '${MangoFormatters.number(_item.maxStock!)} ${_item.unit}'),
                ],
              ),
            ),
            SizedBox(height: dpi.space(18)),

            // ── C.3 Stock por bodega ──
            _sectionLabel(context, 'STOCK POR BODEGA'),
            Container(
              padding: EdgeInsets.all(dpi.space(14)),
              decoration: BoxDecoration(
                color: MangoThemeFactory.cardColor(context),
                borderRadius: BorderRadius.circular(dpi.radius(14)),
                border:
                    Border.all(color: MangoThemeFactory.borderColor(context)),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                          child:
                              Text('BODEGA', style: _colStyle(context, dpi))),
                      SizedBox(
                        width: dpi.scale(70),
                        child: Text('EN MANO',
                            textAlign: TextAlign.right,
                            style: _colStyle(context, dpi)),
                      ),
                      SizedBox(
                        width: dpi.scale(70),
                        child: Text('EN ORDEN',
                            textAlign: TextAlign.right,
                            style: _colStyle(context, dpi)),
                      ),
                    ],
                  ),
                  SizedBox(height: dpi.space(6)),
                  if (_item.byWarehouse.isEmpty)
                    Padding(
                      padding: EdgeInsets.symmetric(vertical: dpi.space(8)),
                      child: Text(
                        'Sin stock registrado en ninguna bodega.',
                        style: TextStyle(
                            fontSize: dpi.font(12),
                            color: MangoThemeFactory.mutedText(context)),
                      ),
                    )
                  else
                    ..._item.byWarehouse.map((w) => Padding(
                          padding:
                              EdgeInsets.symmetric(vertical: dpi.space(4)),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  w.warehouseName,
                                  style: TextStyle(
                                      fontSize: dpi.font(12.5),
                                      fontWeight: FontWeight.w600),
                                ),
                              ),
                              SizedBox(
                                width: dpi.scale(70),
                                child: Text(
                                  MangoFormatters.number(w.quantity),
                                  textAlign: TextAlign.right,
                                  style: TextStyle(
                                      fontSize: dpi.font(13),
                                      fontWeight: FontWeight.w800),
                                ),
                              ),
                              SizedBox(
                                width: dpi.scale(70),
                                child: Text(
                                  (_onOrderByWh[w.warehouseId] ?? 0) > 0
                                      ? '+${MangoFormatters.number(_onOrderByWh[w.warehouseId]!)}'
                                      : '—',
                                  textAlign: TextAlign.right,
                                  style: TextStyle(
                                    fontSize: dpi.font(13),
                                    fontWeight: FontWeight.w700,
                                    color: (_onOrderByWh[w.warehouseId] ?? 0) >
                                            0
                                        ? MangoThemeFactory.info
                                        : MangoThemeFactory.mutedText(context),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        )),
                  Divider(color: MangoThemeFactory.borderColor(context)),
                  Row(
                    children: [
                      Expanded(
                        child: Text('Disponible (en mano − comprometido)',
                            style: TextStyle(
                                fontSize: dpi.font(11.5),
                                color: MangoThemeFactory.mutedText(context))),
                      ),
                      Container(
                        padding: EdgeInsets.symmetric(
                            horizontal: dpi.space(10),
                            vertical: dpi.space(3)),
                        decoration: BoxDecoration(
                          color: (available <= 0 ||
                                  (_item.minStock > 0 &&
                                      available < _item.minStock))
                              ? MangoThemeFactory.danger.withValues(alpha: 0.12)
                              : MangoThemeFactory.success
                                  .withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          '${MangoFormatters.number(available)} ${_item.unit}',
                          style: TextStyle(
                            fontSize: dpi.font(12.5),
                            fontWeight: FontWeight.w800,
                            color: (available <= 0 ||
                                    (_item.minStock > 0 &&
                                        available < _item.minStock))
                                ? MangoThemeFactory.danger
                                : MangoThemeFactory.success,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            SizedBox(height: dpi.space(10)),

            // ── Cobertura + Agregar a orden ──
            Container(
              padding: EdgeInsets.all(dpi.space(14)),
              decoration: BoxDecoration(
                color: MangoThemeFactory.mango.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(dpi.radius(14)),
                border: Border.all(
                    color: MangoThemeFactory.mango.withValues(alpha: 0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.timelapse_rounded,
                          size: dpi.icon(16), color: MangoThemeFactory.mango),
                      SizedBox(width: dpi.space(6)),
                      Expanded(
                        child: Text(
                          _coverageDays != null
                              ? 'Cobertura: ~${_coverageDays!.toStringAsFixed(0)} día(s) al ritmo de venta de 28 días'
                              : 'Sin ventas registradas en 28 días para estimar cobertura',
                          style: TextStyle(
                            fontSize: dpi.font(12),
                            fontWeight: FontWeight.w700,
                            color: MangoThemeFactory.textColor(context),
                          ),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: dpi.space(10)),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _addToPurchaseOrder,
                      style: FilledButton.styleFrom(
                        backgroundColor: MangoThemeFactory.mango,
                        padding:
                            EdgeInsets.symmetric(vertical: dpi.space(12)),
                      ),
                      icon: const Icon(Icons.add_shopping_cart_rounded,
                          size: 18),
                      label: const Text('Agregar a orden de compra'),
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: dpi.space(18)),

            // ── C.4 Kardex ──
            _sectionLabel(context, 'KARDEX (ÚLTIMOS MOVIMIENTOS)'),
            if (_kardex.isEmpty)
              Container(
                padding: EdgeInsets.all(dpi.space(18)),
                decoration: BoxDecoration(
                  color: MangoThemeFactory.cardColor(context),
                  borderRadius: BorderRadius.circular(dpi.radius(14)),
                  border: Border.all(
                      color: MangoThemeFactory.borderColor(context)),
                ),
                child: Text(
                  'Sin movimientos todavía.',
                  style:
                      TextStyle(color: MangoThemeFactory.mutedText(context)),
                ),
              )
            else
              ..._kardex.map((k) => _kardexTile(context, dpi, k)),
            SizedBox(height: dpi.space(24)),
          ],
        ),
      ),
    );
  }

  Widget _econTile(BuildContext context, String label, String value,
      {Color? valueColor}) {
    final dpi = DpiScale.of(context);
    return Expanded(
      child: Container(
        padding: EdgeInsets.symmetric(
            horizontal: dpi.space(10), vertical: dpi.space(12)),
        decoration: BoxDecoration(
          color: MangoThemeFactory.cardColor(context),
          borderRadius: BorderRadius.circular(dpi.radius(14)),
          border: Border.all(color: MangoThemeFactory.borderColor(context)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: dpi.font(8.5),
                fontWeight: FontWeight.w800,
                letterSpacing: 0.4,
                color: MangoThemeFactory.mutedText(context),
              ),
            ),
            SizedBox(height: dpi.space(3)),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                style: TextStyle(
                  fontSize: dpi.font(14),
                  fontWeight: FontWeight.w800,
                  color: valueColor ?? MangoThemeFactory.textColor(context),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionLabel(BuildContext context, String text) {
    final dpi = DpiScale.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: dpi.space(8)),
      child: Text(
        text,
        style: TextStyle(
          fontSize: dpi.font(10),
          fontWeight: FontWeight.w800,
          letterSpacing: 0.6,
          color: MangoThemeFactory.mutedText(context),
        ),
      ),
    );
  }

  Widget _detailRow(BuildContext context, String label, String value,
      {bool monospace = false}) {
    final dpi = DpiScale.of(context);
    return Padding(
      padding: EdgeInsets.symmetric(vertical: dpi.space(6)),
      child: Row(
        children: [
          Expanded(
            child: Text(label,
                style: TextStyle(
                    fontSize: dpi.font(12),
                    color: MangoThemeFactory.mutedText(context))),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: dpi.font(12.5),
              fontWeight: FontWeight.w700,
              fontFamily: monospace ? 'monospace' : null,
              color: MangoThemeFactory.textColor(context),
            ),
          ),
        ],
      ),
    );
  }

  TextStyle _colStyle(BuildContext context, DpiScale dpi) => TextStyle(
        fontSize: dpi.font(9),
        fontWeight: FontWeight.w800,
        letterSpacing: 0.4,
        color: MangoThemeFactory.mutedText(context),
      );

  Widget _kardexTile(BuildContext context, DpiScale dpi, KardexEntry k) {
    final positive = k.quantity > 0;
    final color = positive ? MangoThemeFactory.success : MangoThemeFactory.danger;
    return Container(
      margin: EdgeInsets.only(bottom: dpi.space(6)),
      padding: EdgeInsets.symmetric(
          horizontal: dpi.space(12), vertical: dpi.space(10)),
      decoration: BoxDecoration(
        color: MangoThemeFactory.cardColor(context),
        borderRadius: BorderRadius.circular(dpi.radius(12)),
        border: Border.all(color: MangoThemeFactory.borderColor(context)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  k.typeLabel +
                      (k.reasonCode != null ? ' · ${k.reasonCode}' : ''),
                  style: TextStyle(
                      fontSize: dpi.font(12.5), fontWeight: FontWeight.w700),
                ),
                SizedBox(height: dpi.space(1)),
                Text(
                  [
                    if (k.createdAt != null)
                      MangoFormatters.dateTime(k.createdAt!),
                    if (k.warehouseName != null) k.warehouseName!,
                    if (k.createdByName != null) k.createdByName!,
                  ].join(' · '),
                  style: TextStyle(
                      fontSize: dpi.font(10.5),
                      color: MangoThemeFactory.mutedText(context)),
                ),
                if (k.notes != null && k.notes!.trim().isNotEmpty) ...[
                  SizedBox(height: dpi.space(2)),
                  Text(
                    k.notes!.trim(),
                    style: TextStyle(
                        fontSize: dpi.font(10.5),
                        fontStyle: FontStyle.italic,
                        color: MangoThemeFactory.mutedText(context)),
                  ),
                ],
              ],
            ),
          ),
          SizedBox(width: dpi.space(8)),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${positive ? '+' : ''}${MangoFormatters.number(k.quantity)}',
                style: TextStyle(
                    fontSize: dpi.font(13.5),
                    fontWeight: FontWeight.w800,
                    color: color),
              ),
              Text(
                'saldo ${MangoFormatters.number(k.runningBalance)}',
                style: TextStyle(
                    fontSize: dpi.font(10),
                    color: MangoThemeFactory.mutedText(context)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Ajuste manual: bodega + cantidad contada + motivo obligatorio del catálogo
/// (`other` exige notas). El delta lo calcula el servidor.
class _AdjustDialog extends StatefulWidget {
  const _AdjustDialog({required this.item});

  final InventoryItemSnapshot item;

  @override
  State<_AdjustDialog> createState() => _AdjustDialogState();
}

class _AdjustDialogState extends State<_AdjustDialog> {
  final _qty = TextEditingController();
  final _notes = TextEditingController();
  String? _warehouseId;
  String _reason = 'correction';

  static const _reasons = [
    ('correction', 'Corrección'),
    ('physical_count', 'Conteo físico'),
    ('breakage', 'Rotura / daño'),
    ('expiration', 'Vencimiento'),
    ('theft', 'Robo'),
    ('donation', 'Donación'),
    ('other', 'Otro (especificar)'),
  ];

  @override
  void initState() {
    super.initState();
    if (widget.item.byWarehouse.isNotEmpty) {
      _warehouseId = widget.item.byWarehouse.first.warehouseId;
    }
  }

  @override
  void dispose() {
    _qty.dispose();
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Ajustar stock'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.item.byWarehouse.length > 1)
              DropdownButtonFormField<String>(
                initialValue: _warehouseId,
                decoration: const InputDecoration(labelText: 'Bodega'),
                items: [
                  for (final w in widget.item.byWarehouse)
                    DropdownMenuItem(
                        value: w.warehouseId, child: Text(w.warehouseName)),
                ],
                onChanged: (v) => setState(() => _warehouseId = v),
              ),
            TextField(
              controller: _qty,
              autofocus: true,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: 'Cantidad REAL contada (${widget.item.unit})',
                helperText: 'El sistema calcula la diferencia y la registra.',
              ),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              initialValue: _reason,
              decoration: const InputDecoration(labelText: 'Motivo'),
              items: [
                for (final r in _reasons)
                  DropdownMenuItem(value: r.$1, child: Text(r.$2)),
              ],
              onChanged: (v) => setState(() => _reason = v ?? 'correction'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _notes,
              decoration: InputDecoration(
                labelText:
                    _reason == 'other' ? 'Notas (obligatorio)' : 'Notas',
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () {
            final counted =
                double.tryParse(_qty.text.trim().replaceAll(',', '.'));
            final wh = _warehouseId;
            if (counted == null || counted < 0 || wh == null) return;
            if (_reason == 'other' && _notes.text.trim().isEmpty) return;
            Navigator.of(context).pop((
              warehouseId: wh,
              counted: counted,
              reason: _reason,
              notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
            ));
          },
          child: const Text('Registrar ajuste'),
        ),
      ],
    );
  }
}

/// Punto de reorden y stock máximo.
class _LimitsDialog extends StatefulWidget {
  const _LimitsDialog({required this.item});

  final InventoryItemSnapshot item;

  @override
  State<_LimitsDialog> createState() => _LimitsDialogState();
}

class _LimitsDialogState extends State<_LimitsDialog> {
  late final TextEditingController _min;
  late final TextEditingController _max;

  @override
  void initState() {
    super.initState();
    _min = TextEditingController(
        text: widget.item.minStock > 0
            ? widget.item.minStock.toString()
            : '');
    _max = TextEditingController(
        text: widget.item.maxStock?.toString() ?? '');
  }

  @override
  void dispose() {
    _min.dispose();
    _max.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Puntos de reorden'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _min,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: 'Punto de reorden (${widget.item.unit})',
              helperText: 'Bajo este nivel el artículo aparece en rojo.',
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _max,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: 'Stock máximo (opcional, ${widget.item.unit})',
              helperText: 'Define cuánto sugerir al reponer.',
            ),
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
            final min =
                double.tryParse(_min.text.trim().replaceAll(',', '.')) ?? 0;
            final max =
                double.tryParse(_max.text.trim().replaceAll(',', '.'));
            Navigator.of(context).pop((min: min, max: max));
          },
          child: const Text('Guardar'),
        ),
      ],
    );
  }
}
