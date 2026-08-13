import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/di/providers.dart';
import '../../../core/formatters/mango_formatters.dart';
import '../../../core/responsive/dpi_scale.dart';
import '../../../domain/inventory/inventory_models.dart';
import '../../../domain/inventory/stock_transfer_models.dart';
import '../../auth/viewmodel/auth_gate_view_model.dart';
import '../../theme/theme_data_factory.dart';
import '../../widgets/soft_item_picker_sheet.dart';

/// Transferencias entre bodegas (PRD 6.2): lista con estado, creación
/// (origen → destino + líneas del inventario) y recepción en destino con
/// cantidades ajustables — el faltante queda auditado como merma en
/// tránsito por el backend.
class TransfersView extends ConsumerStatefulWidget {
  const TransfersView({super.key});

  @override
  ConsumerState<TransfersView> createState() => _TransfersViewState();
}

class _TransfersViewState extends ConsumerState<TransfersView> {
  List<StockTransfer> _transfers = const [];
  bool _loading = true;

  String? get _businessId =>
      ref.read(authGateViewModelProvider).profile?.businessId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final businessId = _businessId;
    if (businessId == null) return;
    try {
      final transfers =
          await ref.read(stockTransferServiceProvider).loadTransfers(businessId);
      if (mounted) {
        setState(() {
          _transfers = transfers;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _snack(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  Future<void> _newTransfer() async {
    final businessId = _businessId;
    if (businessId == null) return;
    List<WarehouseInfo> warehouses;
    List<InventoryItemSnapshot> inventory;
    try {
      final results = await Future.wait([
        ref.read(purchasingDataServiceProvider).loadWarehouses(businessId),
        ref.read(inventoryDataServiceProvider).loadInventory(businessId),
      ]);
      warehouses = (results[0] as List<WarehouseInfo>)
          .where((w) => !w.name.contains('__IN_TRANSIT__'))
          .toList(growable: false);
      inventory = results[1] as List<InventoryItemSnapshot>;
    } catch (_) {
      _snack('No se pudo cargar bodegas e inventario.');
      return;
    }
    if (!mounted) return;
    if (warehouses.length < 2) {
      _snack('Necesitas al menos dos bodegas para transferir.');
      return;
    }
    final sent = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => _TransferFormView(
          businessId: businessId,
          warehouses: warehouses,
          inventory: inventory,
        ),
      ),
    );
    if (sent == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    final dpi = DpiScale.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Transferencias'), centerTitle: false),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _newTransfer,
        backgroundColor: MangoThemeFactory.mango,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.swap_horiz_rounded),
        label: const Text('Nueva transferencia'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: _transfers.isEmpty
                  ? ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: EdgeInsets.all(dpi.space(24)),
                      children: [
                        SizedBox(height: dpi.space(60)),
                        Icon(Icons.swap_horiz_rounded,
                            size: dpi.icon(48),
                            color: MangoThemeFactory.mutedText(context)
                                .withValues(alpha: 0.5)),
                        SizedBox(height: dpi.space(12)),
                        Text(
                          'Sin transferencias todavía.\nMueve stock entre bodegas con el botón de abajo.',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ],
                    )
                  : ListView.builder(
                      physics: const AlwaysScrollableScrollPhysics(
                          parent: BouncingScrollPhysics()),
                      padding: EdgeInsets.fromLTRB(dpi.space(16),
                          dpi.space(12), dpi.space(16), dpi.space(96)),
                      itemCount: _transfers.length,
                      itemBuilder: (context, index) {
                        final t = _transfers[index];
                        return _TransferCard(
                          transfer: t,
                          onTap: () async {
                            await Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) =>
                                    TransferDetailView(transfer: t),
                              ),
                            );
                            _load();
                          },
                        );
                      },
                    ),
            ),
    );
  }
}

Color _transferStatusColor(String status) {
  switch (status) {
    case 'pending_approval':
      return MangoThemeFactory.info;
    case 'sent':
      return MangoThemeFactory.warning;
    case 'received':
      return MangoThemeFactory.success;
    case 'cancelled':
      return MangoThemeFactory.danger;
    default:
      return MangoThemeFactory.info;
  }
}

class _TransferCard extends StatelessWidget {
  const _TransferCard({required this.transfer, required this.onTap});

  final StockTransfer transfer;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final dpi = DpiScale.of(context);
    final t = transfer;
    final color = _transferStatusColor(t.status);
    return Container(
      margin: EdgeInsets.only(bottom: dpi.space(8)),
      decoration: BoxDecoration(
        color: MangoThemeFactory.cardColor(context),
        borderRadius: BorderRadius.circular(dpi.radius(14)),
        border: Border.all(color: MangoThemeFactory.borderColor(context)),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(dpi.radius(14)),
          child: Padding(
            padding: EdgeInsets.all(dpi.space(14)),
            child: Row(
              children: [
                Container(
                  width: dpi.scale(40),
                  height: dpi.scale(40),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(dpi.radius(12)),
                  ),
                  child: Icon(Icons.swap_horiz_rounded,
                      color: color, size: dpi.icon(20)),
                ),
                SizedBox(width: dpi.space(12)),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${t.fromWarehouseName ?? '?'} → ${t.isCrossBusiness ? (t.toBusinessName ?? '') : (t.toWarehouseName ?? '?')}',
                        style: TextStyle(
                            fontSize: dpi.font(13.5),
                            fontWeight: FontWeight.w700),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      SizedBox(height: dpi.space(2)),
                      Text(
                        [
                          t.number,
                          '${t.itemCount} ítem(s)',
                          if (t.sentAt != null)
                            MangoFormatters.date(t.sentAt!),
                        ].join(' · '),
                        style: TextStyle(
                          fontSize: dpi.font(11),
                          color: MangoThemeFactory.mutedText(context),
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: EdgeInsets.symmetric(
                      horizontal: dpi.space(8), vertical: dpi.space(3)),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(dpi.radius(6)),
                  ),
                  child: Text(
                    t.statusLabel.toUpperCase(),
                    style: TextStyle(
                      fontSize: dpi.font(9),
                      fontWeight: FontWeight.w800,
                      color: color,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Detalle: líneas enviadas/recibidas + acciones según estado.
class TransferDetailView extends ConsumerStatefulWidget {
  const TransferDetailView({super.key, required this.transfer});

  final StockTransfer transfer;

  @override
  ConsumerState<TransferDetailView> createState() =>
      _TransferDetailViewState();
}

class _TransferDetailViewState extends ConsumerState<TransferDetailView> {
  List<StockTransferItem> _items = const [];
  bool _loading = true;
  bool _saving = false;

  StockTransfer get _t => widget.transfer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    try {
      final items =
          await ref.read(stockTransferServiceProvider).loadItems(_t.id);
      if (mounted) {
        setState(() {
          _items = items;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _snack(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  Future<void> _run(Future<void> Function() action, String okMsg) async {
    setState(() => _saving = true);
    try {
      await action();
      if (!mounted) return;
      _snack(okMsg);
      Navigator.of(context).pop();
    } catch (_) {
      if (mounted) _snack('No se pudo completar la operación.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _receive() async {
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => _ReceiveTransferView(transfer: _t, items: _items),
      ),
    );
    if (result == true && mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final dpi = DpiScale.of(context);
    final color = _transferStatusColor(_t.status);
    return Scaffold(
      appBar: AppBar(title: Text(_t.number), centerTitle: false),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: EdgeInsets.all(dpi.space(16)),
              children: [
                Container(
                  padding: EdgeInsets.all(dpi.space(14)),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.07),
                    borderRadius: BorderRadius.circular(dpi.radius(14)),
                    border:
                        Border.all(color: color.withValues(alpha: 0.35)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${_t.fromWarehouseName ?? '?'} → ${_t.isCrossBusiness ? (_t.toBusinessName ?? '') : (_t.toWarehouseName ?? '?')}',
                        style: TextStyle(
                            fontSize: dpi.font(15),
                            fontWeight: FontWeight.w800),
                      ),
                      SizedBox(height: dpi.space(4)),
                      Text(
                        [
                          _t.statusLabel,
                          if (_t.createdByName != null)
                            'Por ${_t.createdByName}',
                          if (_t.sentAt != null)
                            MangoFormatters.dateTime(_t.sentAt!),
                        ].join(' · '),
                        style: TextStyle(
                            fontSize: dpi.font(11),
                            color: MangoThemeFactory.mutedText(context)),
                      ),
                      if (_t.notes != null &&
                          _t.notes!.trim().isNotEmpty) ...[
                        SizedBox(height: dpi.space(6)),
                        Text(_t.notes!.trim(),
                            style: TextStyle(
                                fontSize: dpi.font(11.5),
                                fontStyle: FontStyle.italic)),
                      ],
                    ],
                  ),
                ),
                SizedBox(height: dpi.space(14)),
                ..._items.map((i) {
                  final variance = i.variance;
                  return Container(
                    margin: EdgeInsets.only(bottom: dpi.space(6)),
                    padding: EdgeInsets.symmetric(
                        horizontal: dpi.space(12), vertical: dpi.space(10)),
                    decoration: BoxDecoration(
                      color: MangoThemeFactory.cardColor(context),
                      borderRadius: BorderRadius.circular(dpi.radius(12)),
                      border: Border.all(
                          color: MangoThemeFactory.borderColor(context)),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            i.itemName ?? 'Ítem',
                            style: TextStyle(
                                fontSize: dpi.font(13),
                                fontWeight: FontWeight.w600),
                          ),
                        ),
                        Text(
                          i.quantityReceived != null
                              ? '${MangoFormatters.number(i.quantityReceived!)}/${MangoFormatters.number(i.quantitySent)} ${i.unit ?? ''}'
                              : '${MangoFormatters.number(i.quantitySent)} ${i.unit ?? ''}',
                          style: TextStyle(
                            fontSize: dpi.font(13),
                            fontWeight: FontWeight.w800,
                            color: variance != null && variance < 0
                                ? MangoThemeFactory.danger
                                : MangoThemeFactory.textColor(context),
                          ),
                        ),
                      ],
                    ),
                  );
                }),
                SizedBox(height: dpi.space(16)),
                if (_t.isPendingApproval) ...[
                  FilledButton.icon(
                    onPressed: _saving
                        ? null
                        : () => _run(
                            () => ref
                                .read(stockTransferServiceProvider)
                                .approve(_t.id),
                            'Transferencia aprobada: el stock salió en tránsito.'),
                    style: FilledButton.styleFrom(
                      backgroundColor: MangoThemeFactory.success,
                      padding:
                          EdgeInsets.symmetric(vertical: dpi.space(13)),
                    ),
                    icon: const Icon(Icons.check_circle_rounded),
                    label: const Text('Aprobar y enviar'),
                  ),
                  SizedBox(height: dpi.space(8)),
                ],
                if (_t.isInTransit) ...[
                  FilledButton.icon(
                    onPressed: _saving ? null : _receive,
                    style: FilledButton.styleFrom(
                      backgroundColor: MangoThemeFactory.mango,
                      padding:
                          EdgeInsets.symmetric(vertical: dpi.space(13)),
                    ),
                    icon: const Icon(Icons.inventory_rounded),
                    label: const Text('Recibir en destino'),
                  ),
                  SizedBox(height: dpi.space(8)),
                ],
                if (_t.isPendingApproval || _t.isInTransit)
                  TextButton.icon(
                    onPressed: _saving
                        ? null
                        : () => _run(
                            () => ref
                                .read(stockTransferServiceProvider)
                                .cancel(_t.id),
                            'Transferencia cancelada: el stock volvió al origen.'),
                    style: TextButton.styleFrom(
                        foregroundColor: MangoThemeFactory.danger),
                    icon: const Icon(Icons.cancel_outlined, size: 18),
                    label: const Text('Cancelar transferencia'),
                  ),
              ],
            ),
    );
  }
}

/// Recepción en destino: cantidad recibida por línea (prellenada con lo
/// enviado); un faltante genera el ajuste de tránsito en el backend.
class _ReceiveTransferView extends ConsumerStatefulWidget {
  const _ReceiveTransferView({required this.transfer, required this.items});

  final StockTransfer transfer;
  final List<StockTransferItem> items;

  @override
  ConsumerState<_ReceiveTransferView> createState() =>
      _ReceiveTransferViewState();
}

class _ReceiveTransferViewState extends ConsumerState<_ReceiveTransferView> {
  late final Map<String, TextEditingController> _qty;
  final _notes = TextEditingController();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _qty = {
      for (final i in widget.items)
        i.id: TextEditingController(
            text: i.quantitySent.truncateToDouble() == i.quantitySent
                ? i.quantitySent.toInt().toString()
                : i.quantitySent.toString()),
    };
  }

  @override
  void dispose() {
    for (final c in _qty.values) {
      c.dispose();
    }
    _notes.dispose();
    super.dispose();
  }

  bool get _hasShortage => widget.items.any((i) {
        final v = double.tryParse(
                _qty[i.id]!.text.trim().replaceAll(',', '.')) ??
            0;
        return v < i.quantitySent;
      });

  Future<void> _submit() async {
    final received = <Map<String, dynamic>>[];
    for (final i in widget.items) {
      final v =
          double.tryParse(_qty[i.id]!.text.trim().replaceAll(',', '.'));
      if (v == null || v < 0) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content:
                Text('Cantidad inválida en "${i.itemName ?? 'ítem'}".')));
        return;
      }
      received.add({'transfer_item_id': i.id, 'quantity_received': v});
    }
    setState(() => _saving = true);
    try {
      await ref.read(stockTransferServiceProvider).receive(
            transferId: widget.transfer.id,
            receivedItems: received,
            varianceNotes:
                _notes.text.trim().isEmpty ? null : _notes.text.trim(),
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Transferencia recibida: stock actualizado.')));
      Navigator.of(context).pop(true);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('No se pudo recibir la transferencia.')));
      setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dpi = DpiScale.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text('Recibir ${widget.transfer.number}'),
        centerTitle: false,
      ),
      bottomNavigationBar: SafeArea(
        child: Container(
          padding: EdgeInsets.fromLTRB(
              dpi.space(16), dpi.space(10), dpi.space(16), dpi.space(12)),
          decoration: BoxDecoration(
            color: MangoThemeFactory.cardColor(context),
            border: Border(
                top: BorderSide(
                    color: MangoThemeFactory.borderColor(context))),
          ),
          child: FilledButton.icon(
            onPressed: _saving ? null : _submit,
            style: FilledButton.styleFrom(
              backgroundColor: MangoThemeFactory.mango,
              padding: EdgeInsets.symmetric(vertical: dpi.space(13)),
            ),
            icon: _saving
                ? SizedBox(
                    width: dpi.icon(16),
                    height: dpi.icon(16),
                    child: const CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.check_circle_rounded),
            label: Text(_saving ? 'Recibiendo…' : 'Confirmar recepción'),
          ),
        ),
      ),
      body: ListView(
        padding: EdgeInsets.all(dpi.space(16)),
        children: [
          Text(
            'Ajusta lo que llegó físicamente. Un faltante queda auditado como pérdida en tránsito.',
            style: TextStyle(
                fontSize: dpi.font(12),
                color: MangoThemeFactory.mutedText(context)),
          ),
          SizedBox(height: dpi.space(12)),
          ...widget.items.map((i) => Container(
                margin: EdgeInsets.only(bottom: dpi.space(8)),
                padding: EdgeInsets.all(dpi.space(12)),
                decoration: BoxDecoration(
                  color: MangoThemeFactory.cardColor(context),
                  borderRadius: BorderRadius.circular(dpi.radius(12)),
                  border: Border.all(
                      color: MangoThemeFactory.borderColor(context)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(i.itemName ?? 'Ítem',
                              style: TextStyle(
                                  fontSize: dpi.font(13),
                                  fontWeight: FontWeight.w600)),
                          Text(
                            'Enviado: ${MangoFormatters.number(i.quantitySent)} ${i.unit ?? ''}',
                            style: TextStyle(
                                fontSize: dpi.font(10.5),
                                color:
                                    MangoThemeFactory.mutedText(context)),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(width: dpi.space(10)),
                    SizedBox(
                      width: dpi.scale(90),
                      child: TextField(
                        controller: _qty[i.id],
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        textAlign: TextAlign.right,
                        onChanged: (_) => setState(() {}),
                        decoration: const InputDecoration(
                            labelText: 'Recibido', isDense: true),
                      ),
                    ),
                  ],
                ),
              )),
          if (_hasShortage) ...[
            SizedBox(height: dpi.space(8)),
            TextField(
              controller: _notes,
              decoration: const InputDecoration(
                labelText: 'Nota del faltante (recomendado)',
                hintText: 'Ej. caja dañada en el camión',
              ),
            ),
          ],
          SizedBox(height: dpi.space(24)),
        ],
      ),
    );
  }
}

/// Crear transferencia: origen → destino + líneas del inventario.
class _TransferFormView extends ConsumerStatefulWidget {
  const _TransferFormView({
    required this.businessId,
    required this.warehouses,
    required this.inventory,
  });

  final String businessId;
  final List<WarehouseInfo> warehouses;
  final List<InventoryItemSnapshot> inventory;

  @override
  ConsumerState<_TransferFormView> createState() => _TransferFormViewState();
}

class _TransferLine {
  _TransferLine(this.item) : qty = TextEditingController(text: '1');
  final InventoryItemSnapshot item;
  final TextEditingController qty;

  double get qtyValue =>
      double.tryParse(qty.text.trim().replaceAll(',', '.')) ?? 0;
}

class _TransferFormViewState extends ConsumerState<_TransferFormView> {
  final _notes = TextEditingController();
  final List<_TransferLine> _lines = [];
  String? _fromId;
  String? _toId;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _fromId = widget.warehouses.first.id;
    _toId = widget.warehouses.length > 1 ? widget.warehouses[1].id : null;
  }

  @override
  void dispose() {
    for (final l in _lines) {
      l.qty.dispose();
    }
    _notes.dispose();
    super.dispose();
  }

  void _snack(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  /// Stock del ítem en la bodega ORIGEN (lo transferible).
  double _stockInFrom(InventoryItemSnapshot item) {
    for (final w in item.byWarehouse) {
      if (w.warehouseId == _fromId) return w.quantity;
    }
    return 0;
  }

  Future<void> _addLine() async {
    // Solo artículos con stock en la bodega origen (regla de Square).
    final available = widget.inventory
        .where((i) => _stockInFrom(i) > 0)
        .toList(growable: false);
    if (available.isEmpty) {
      _snack('La bodega origen no tiene stock disponible.');
      return;
    }
    final item = await showSoftItemPicker(
      context: context,
      items: available,
      subtitleOf: (i) =>
          'En origen: ${MangoFormatters.number(_stockInFrom(i))} ${i.unit}',
    );
    if (item == null || !mounted) return;
    if (_lines.any((l) => l.item.itemId == item.itemId)) return;
    setState(() => _lines.add(_TransferLine(item)));
  }

  Future<void> _send() async {
    final from = _fromId;
    final to = _toId;
    if (from == null || to == null || from == to) {
      _snack('Elige bodegas de origen y destino distintas.');
      return;
    }
    if (_lines.isEmpty) {
      _snack('Agrega al menos un artículo.');
      return;
    }
    for (final l in _lines) {
      if (l.qtyValue <= 0) {
        _snack('Cantidad inválida en "${l.item.name}".');
        return;
      }
      if (l.qtyValue > _stockInFrom(l.item)) {
        _snack(
            '"${l.item.name}" solo tiene ${MangoFormatters.number(_stockInFrom(l.item))} en la bodega origen.');
        return;
      }
    }
    setState(() => _saving = true);
    try {
      await ref.read(stockTransferServiceProvider).send(
            businessId: widget.businessId,
            fromWarehouseId: from,
            toWarehouseId: to,
            items: [
              for (final l in _lines)
                {'item_id': l.item.itemId, 'quantity': l.qtyValue},
            ],
            notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
          );
      if (!mounted) return;
      _snack('Transferencia enviada.');
      Navigator.of(context).pop(true);
    } catch (_) {
      if (!mounted) return;
      _snack('No se pudo enviar la transferencia.');
      setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dpi = DpiScale.of(context);
    return Scaffold(
      appBar:
          AppBar(title: const Text('Nueva transferencia'), centerTitle: false),
      bottomNavigationBar: SafeArea(
        child: Container(
          padding: EdgeInsets.fromLTRB(
              dpi.space(16), dpi.space(10), dpi.space(16), dpi.space(12)),
          decoration: BoxDecoration(
            color: MangoThemeFactory.cardColor(context),
            border: Border(
                top: BorderSide(
                    color: MangoThemeFactory.borderColor(context))),
          ),
          child: FilledButton.icon(
            onPressed: _saving ? null : _send,
            style: FilledButton.styleFrom(
              backgroundColor: MangoThemeFactory.mango,
              padding: EdgeInsets.symmetric(vertical: dpi.space(13)),
            ),
            icon: _saving
                ? SizedBox(
                    width: dpi.icon(16),
                    height: dpi.icon(16),
                    child: const CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.send_rounded),
            label: Text(_saving ? 'Enviando…' : 'Enviar transferencia'),
          ),
        ),
      ),
      body: ListView(
        padding: EdgeInsets.all(dpi.space(16)),
        children: [
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: _fromId,
                  decoration: const InputDecoration(labelText: 'Origen'),
                  items: [
                    for (final w in widget.warehouses)
                      DropdownMenuItem(value: w.id, child: Text(w.name)),
                  ],
                  onChanged: (v) => setState(() => _fromId = v),
                ),
              ),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: dpi.space(8)),
                child: Icon(Icons.arrow_forward_rounded,
                    size: dpi.icon(18),
                    color: MangoThemeFactory.mutedText(context)),
              ),
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: _toId,
                  decoration: const InputDecoration(labelText: 'Destino'),
                  items: [
                    for (final w in widget.warehouses)
                      DropdownMenuItem(value: w.id, child: Text(w.name)),
                  ],
                  onChanged: (v) => setState(() => _toId = v),
                ),
              ),
            ],
          ),
          SizedBox(height: dpi.space(14)),
          Row(
            children: [
              Expanded(
                child: Text(
                  'ARTÍCULOS (${_lines.length})',
                  style: TextStyle(
                    fontSize: dpi.font(10),
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.6,
                    color: MangoThemeFactory.mutedText(context),
                  ),
                ),
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
                'Solo se listan artículos con stock en la bodega origen.',
                style: TextStyle(
                    fontSize: dpi.font(12),
                    color: MangoThemeFactory.mutedText(context)),
              ),
            )
          else
            ...List.generate(_lines.length, (index) {
              final l = _lines[index];
              final max = _stockInFrom(l.item);
              return Container(
                margin: EdgeInsets.only(bottom: dpi.space(8)),
                padding: EdgeInsets.all(dpi.space(12)),
                decoration: BoxDecoration(
                  color: MangoThemeFactory.cardColor(context),
                  borderRadius: BorderRadius.circular(dpi.radius(12)),
                  border: Border.all(
                      color: MangoThemeFactory.borderColor(context)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(l.item.name,
                              style: TextStyle(
                                  fontSize: dpi.font(13),
                                  fontWeight: FontWeight.w600)),
                          Text(
                            'Disponible en origen: ${MangoFormatters.number(max)} ${l.item.unit}',
                            style: TextStyle(
                                fontSize: dpi.font(10.5),
                                color:
                                    MangoThemeFactory.mutedText(context)),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(width: dpi.space(10)),
                    SizedBox(
                      width: dpi.scale(80),
                      child: TextField(
                        controller: l.qty,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        textAlign: TextAlign.right,
                        decoration: const InputDecoration(
                            labelText: 'Cant.', isDense: true),
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.close_rounded,
                          size: dpi.icon(18),
                          color: MangoThemeFactory.mutedText(context)),
                      onPressed: () => setState(() {
                        _lines.removeAt(index).qty.dispose();
                      }),
                    ),
                  ],
                ),
              );
            }),
          SizedBox(height: dpi.space(8)),
          TextField(
            controller: _notes,
            decoration:
                const InputDecoration(labelText: 'Notas (opcional)'),
          ),
          SizedBox(height: dpi.space(24)),
        ],
      ),
    );
  }
}
