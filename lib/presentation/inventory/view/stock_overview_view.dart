import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/di/providers.dart';
import '../../../core/formatters/mango_formatters.dart';
import '../../../core/responsive/dpi_scale.dart';
import '../../../domain/inventory/inventory_models.dart';
import '../../auth/viewmodel/auth_gate_view_model.dart';
import '../../purchasing/view/direct_reception_view.dart';
import '../../purchasing/view/reception_scanner_page.dart';
import '../../theme/theme_data_factory.dart';
import '../viewmodel/inventory_view_model.dart';
import 'shopping_list_view.dart';

enum _StockSort { lowestFirst, highestFirst, alphabetical }

/// Stock overview al estilo Square for Retail: tabla de insumos con
/// En mano / En camino, búsqueda por nombre/SKU/código (con escáner en el
/// campo), orden "menor stock primero" y el botón primario "Recibir stock".
/// Vive dentro del hub de Inventario (content-only, sin Scaffold).
class StockOverviewView extends ConsumerStatefulWidget {
  const StockOverviewView({super.key});

  @override
  ConsumerState<StockOverviewView> createState() => _StockOverviewViewState();
}

class _StockOverviewViewState extends ConsumerState<StockOverviewView> {
  String _query = '';
  _StockSort _sort = _StockSort.lowestFirst;
  Map<String, double> _onOrder = const {};
  Map<String, String> _codeToItem = const {};
  String? _scannedItemId;

  String? get _businessId =>
      ref.read(authGateViewModelProvider).profile?.businessId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    await ref.read(inventoryViewModelProvider.notifier).load();
    final businessId = _businessId;
    if (businessId == null) return;
    try {
      final onOrder = await ref
          .read(purchasingDataServiceProvider)
          .loadOnOrderByItem(businessId);
      if (mounted) setState(() => _onOrder = onOrder);
    } catch (_) {/* la columna En camino queda en 0 */}
    try {
      final items = ref.read(inventoryViewModelProvider).items;
      final codes = await ref
          .read(purchasingDataServiceProvider)
          .loadItemCodes(items.map((i) => i.itemId).toList(growable: false));
      if (mounted) setState(() => _codeToItem = codes);
    } catch (_) {/* búsqueda por escáner deshabilitada */}
  }

  Future<void> _scanToSearch() async {
    if (_codeToItem.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              'Ningún insumo tiene código de barras ni SKU registrado.')));
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ReceptionScannerPage(
          onCode: (code) {
            final itemId = _codeToItem[code];
            if (itemId == null) {
              return const ScanFeedback(
                  matched: false, message: 'Código no registrado');
            }
            setState(() => _scannedItemId = itemId);
            final item = ref
                .read(inventoryViewModelProvider)
                .items
                .where((i) => i.itemId == itemId)
                .firstOrNull;
            return ScanFeedback(
                matched: true,
                message: item != null
                    ? '${item.name} · filtrado'
                    : 'Encontrado');
          },
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  List<InventoryItemSnapshot> _visible(List<InventoryItemSnapshot> items) {
    var list = items;
    if (_scannedItemId != null) {
      list = list.where((i) => i.itemId == _scannedItemId).toList();
    } else if (_query.isNotEmpty) {
      final q = _query.toLowerCase();
      list = list
          .where((i) =>
              i.name.toLowerCase().contains(q) ||
              (i.sku?.toLowerCase().contains(q) ?? false))
          .toList();
    }
    final sorted = [...list];
    switch (_sort) {
      case _StockSort.lowestFirst:
        sorted.sort((a, b) => a.totalQuantity.compareTo(b.totalQuantity));
      case _StockSort.highestFirst:
        sorted.sort((a, b) => b.totalQuantity.compareTo(a.totalQuantity));
      case _StockSort.alphabetical:
        sorted.sort(
            (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    }
    return sorted;
  }

  @override
  Widget build(BuildContext context) {
    final dpi = DpiScale.of(context);
    final state = ref.watch(inventoryViewModelProvider);
    final items = _visible(state.items);
    final lowItems = state.items
        .where((i) => i.isLow || i.isOut)
        .toList(growable: false);

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(
            parent: BouncingScrollPhysics()),
        padding: EdgeInsets.fromLTRB(
            dpi.space(16), dpi.space(4), dpi.space(16), dpi.space(28)),
        children: [
          // ── Acciones principales ──
          Row(
            children: [
              if (lowItems.isNotEmpty)
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                          builder: (_) => ShoppingListView(items: lowItems)),
                    ),
                    style: OutlinedButton.styleFrom(
                      padding:
                          EdgeInsets.symmetric(vertical: dpi.space(12)),
                    ),
                    icon: Icon(Icons.shopping_cart_outlined,
                        size: dpi.icon(16)),
                    label: Text('Lista (${lowItems.length})'),
                  ),
                ),
              if (lowItems.isNotEmpty) SizedBox(width: dpi.space(10)),
              Expanded(
                flex: lowItems.isEmpty ? 1 : 2,
                child: FilledButton.icon(
                  onPressed: () async {
                    await Navigator.of(context).push(
                      MaterialPageRoute(
                          builder: (_) => const DirectReceptionView()),
                    );
                    _load();
                  },
                  style: FilledButton.styleFrom(
                    backgroundColor: MangoThemeFactory.mango,
                    padding: EdgeInsets.symmetric(vertical: dpi.space(12)),
                  ),
                  icon: const Icon(Icons.archive_rounded, size: 18),
                  label: const Text('Recibir stock'),
                ),
              ),
            ],
          ),
          SizedBox(height: dpi.space(12)),

          // ── Búsqueda con escáner ──
          TextField(
            onChanged: (v) => setState(() {
              _query = v;
              _scannedItemId = null;
            }),
            decoration: InputDecoration(
              hintText: 'Buscar nombre, SKU o código…',
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: IconButton(
                tooltip: 'Escanear código',
                icon: const Icon(Icons.qr_code_scanner_rounded),
                onPressed: _scanToSearch,
              ),
            ),
          ),
          if (_scannedItemId != null) ...[
            SizedBox(height: dpi.space(8)),
            Align(
              alignment: Alignment.centerLeft,
              child: InputChip(
                label: const Text('Filtro por escaneo'),
                avatar: const Icon(Icons.qr_code_rounded, size: 16),
                onDeleted: () => setState(() => _scannedItemId = null),
              ),
            ),
          ],
          SizedBox(height: dpi.space(10)),

          // ── Orden + encabezado de columnas ──
          Row(
            children: [
              Expanded(
                child: Text(
                  '${items.length} insumo(s)',
                  style: TextStyle(
                    fontSize: dpi.font(11),
                    color: MangoThemeFactory.mutedText(context),
                  ),
                ),
              ),
              PopupMenuButton<_StockSort>(
                initialValue: _sort,
                onSelected: (v) => setState(() => _sort = v),
                itemBuilder: (_) => const [
                  PopupMenuItem(
                      value: _StockSort.lowestFirst,
                      child: Text('Menor stock primero')),
                  PopupMenuItem(
                      value: _StockSort.highestFirst,
                      child: Text('Mayor stock primero')),
                  PopupMenuItem(
                      value: _StockSort.alphabetical,
                      child: Text('Alfabético')),
                ],
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.swap_vert_rounded,
                        size: dpi.icon(16),
                        color: MangoThemeFactory.mutedText(context)),
                    SizedBox(width: dpi.space(4)),
                    Text(
                      switch (_sort) {
                        _StockSort.lowestFirst => 'Menor primero',
                        _StockSort.highestFirst => 'Mayor primero',
                        _StockSort.alphabetical => 'A–Z',
                      },
                      style: TextStyle(
                        fontSize: dpi.font(11.5),
                        fontWeight: FontWeight.w700,
                        color: MangoThemeFactory.mutedText(context),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: dpi.space(8)),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: dpi.space(14)),
            child: Row(
              children: [
                Expanded(
                  child: Text('INSUMO',
                      style: _colStyle(context, dpi)),
                ),
                SizedBox(
                  width: dpi.scale(74),
                  child: Text('EN MANO',
                      textAlign: TextAlign.right,
                      style: _colStyle(context, dpi)),
                ),
                SizedBox(
                  width: dpi.scale(74),
                  child: Text('EN CAMINO',
                      textAlign: TextAlign.right,
                      style: _colStyle(context, dpi)),
                ),
              ],
            ),
          ),
          SizedBox(height: dpi.space(6)),

          if (state.isLoading && state.items.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 60),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (items.isEmpty)
            Padding(
              padding: EdgeInsets.symmetric(vertical: dpi.space(40)),
              child: Center(
                child: Text(
                  state.items.isEmpty
                      ? 'No hay insumos en el inventario.'
                      : 'Sin resultados para la búsqueda.',
                  style:
                      TextStyle(color: MangoThemeFactory.mutedText(context)),
                ),
              ),
            )
          else
            ...items.map((i) => _StockRow(
                  item: i,
                  onOrder: _onOrder[i.itemId] ?? 0,
                )),
        ],
      ),
    );
  }

  TextStyle _colStyle(BuildContext context, DpiScale dpi) => TextStyle(
        fontSize: dpi.font(9.5),
        fontWeight: FontWeight.w800,
        letterSpacing: 0.5,
        color: MangoThemeFactory.mutedText(context),
      );
}

class _StockRow extends StatelessWidget {
  const _StockRow({required this.item, required this.onOrder});

  final InventoryItemSnapshot item;
  final double onOrder;

  @override
  Widget build(BuildContext context) {
    final dpi = DpiScale.of(context);
    final out = item.isOut;
    final low = item.isLow && !out;
    final qtyColor = out
        ? MangoThemeFactory.danger
        : low
            ? MangoThemeFactory.warning
            : MangoThemeFactory.textColor(context);

    return Container(
      margin: EdgeInsets.only(bottom: dpi.space(6)),
      padding: EdgeInsets.symmetric(
          horizontal: dpi.space(14), vertical: dpi.space(10)),
      decoration: BoxDecoration(
        color: MangoThemeFactory.cardColor(context),
        borderRadius: BorderRadius.circular(dpi.radius(12)),
        border: Border.all(
          color: out
              ? MangoThemeFactory.danger.withValues(alpha: 0.35)
              : MangoThemeFactory.borderColor(context),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.name,
                  style: TextStyle(
                    fontSize: dpi.font(13),
                    fontWeight: FontWeight.w600,
                    color: MangoThemeFactory.textColor(context),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (item.sku != null && item.sku!.isNotEmpty) ...[
                  SizedBox(height: dpi.space(1)),
                  Text(
                    item.sku!,
                    style: TextStyle(
                      fontSize: dpi.font(10.5),
                      fontFamily: 'monospace',
                      color: MangoThemeFactory.mutedText(context),
                    ),
                  ),
                ],
              ],
            ),
          ),
          SizedBox(
            width: dpi.scale(74),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                out
                    ? Container(
                        padding: EdgeInsets.symmetric(
                            horizontal: dpi.space(7),
                            vertical: dpi.space(1)),
                        decoration: BoxDecoration(
                          color:
                              MangoThemeFactory.danger.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          '0',
                          style: TextStyle(
                            fontSize: dpi.font(12),
                            fontWeight: FontWeight.w800,
                            color: MangoThemeFactory.danger,
                          ),
                        ),
                      )
                    : Text(
                        MangoFormatters.number(item.totalQuantity),
                        style: TextStyle(
                          fontSize: dpi.font(13),
                          fontWeight: FontWeight.w800,
                          color: qtyColor,
                        ),
                      ),
                Text(
                  item.unit,
                  style: TextStyle(
                    fontSize: dpi.font(9.5),
                    color: MangoThemeFactory.mutedText(context),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            width: dpi.scale(74),
            child: Text(
              onOrder > 0 ? MangoFormatters.number(onOrder) : '—',
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: dpi.font(13),
                fontWeight:
                    onOrder > 0 ? FontWeight.w800 : FontWeight.w500,
                color: onOrder > 0
                    ? MangoThemeFactory.info
                    : MangoThemeFactory.mutedText(context),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
