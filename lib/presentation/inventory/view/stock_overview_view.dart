import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/di/providers.dart';
import '../../../core/responsive/dpi_scale.dart';
import '../../../domain/inventory/inventory_models.dart';
import '../../auth/viewmodel/auth_gate_view_model.dart';
import '../../catalog/view/product_form_view.dart';
import '../../purchasing/view/direct_reception_view.dart';
import '../../purchasing/view/reception_scanner_page.dart';
import '../../theme/theme_data_factory.dart';
import '../viewmodel/inventory_view_model.dart';
import '../widgets/stock_row.dart';
import 'shopping_list_view.dart';
import 'stock_item_detail_view.dart';

enum _StockSort { lowestFirst, highestFirst, alphabetical }

enum _StockFilter { all, belowMin, onOrder, lowMargin }

/// Pantalla B del PRD 6.2 — Vista de stock: tabla de insumos con
/// En mano / En camino, búsqueda por nombre/SKU/código (con escáner en el
/// campo), orden "menor stock primero", "Recibir stock" y FAB de nuevo
/// artículo. Se abre desde el hub de Inventario.
class StockOverviewView extends ConsumerStatefulWidget {
  const StockOverviewView({super.key});

  @override
  ConsumerState<StockOverviewView> createState() => _StockOverviewViewState();
}

class _StockOverviewViewState extends ConsumerState<StockOverviewView> {
  String _query = '';
  _StockSort _sort = _StockSort.lowestFirst;
  _StockFilter _filter = _StockFilter.all;
  Map<String, double> _onOrder = const {};
  Map<String, double> _committed = const {};
  Map<String, double> _prices = const {};
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
    } catch (_) {/* la columna En orden queda en 0 */}
    try {
      final committed = await ref
          .read(inventoryDataServiceProvider)
          .loadCommittedByItem(businessId);
      if (mounted) setState(() => _committed = committed);
    } catch (_) {/* Disponible = En mano */}
    try {
      final prices = await ref
          .read(inventoryDataServiceProvider)
          .loadLinkedPrices(businessId);
      if (mounted) setState(() => _prices = prices);
    } catch (_) {/* Margen queda en — */}
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

  /// Margen % del insumo con producto vinculado (null sin precio o costo).
  double? _marginOf(InventoryItemSnapshot i) {
    final price = _prices[i.itemId];
    final cost = i.cost;
    if (price == null || price <= 0 || cost == null) return null;
    return (price - cost) / price * 100;
  }

  bool _matchesFilter(InventoryItemSnapshot i) {
    switch (_filter) {
      case _StockFilter.all:
        return true;
      case _StockFilter.belowMin:
        return i.minStock > 0 && i.totalQuantity < i.minStock;
      case _StockFilter.onOrder:
        return (_onOrder[i.itemId] ?? 0) > 0;
      case _StockFilter.lowMargin:
        final m = _marginOf(i);
        return m != null && m < 25;
    }
  }

  int _filterCount(_StockFilter f) {
    final items = ref.read(inventoryViewModelProvider).items;
    final prev = _filter;
    _filter = f;
    final count = items.where(_matchesFilter).length;
    _filter = prev;
    return count;
  }

  List<InventoryItemSnapshot> _visible(List<InventoryItemSnapshot> items) {
    var list = items.where(_matchesFilter).toList();
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

    return Scaffold(
      appBar: AppBar(title: const Text('Vista de stock'), centerTitle: false),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const ProductFormView()),
        ),
        backgroundColor: MangoThemeFactory.mango,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Nuevo artículo'),
      ),
      body: RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(
            parent: BouncingScrollPhysics()),
        padding: EdgeInsets.fromLTRB(
            dpi.space(16), dpi.space(12), dpi.space(16), dpi.space(96)),
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

          // ── Chips de filtro con conteo (PRD 6.2 B.2) ──
          SizedBox(
            height: dpi.scale(34),
            child: ListView(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              children: [
                _filterChip(_StockFilter.all, 'Todos'),
                _filterChip(_StockFilter.belowMin, 'Bajo mínimo'),
                _filterChip(_StockFilter.onOrder, 'En orden'),
                _filterChip(_StockFilter.lowMargin, 'Margen bajo'),
              ],
            ),
          ),
          SizedBox(height: dpi.space(8)),
          Row(
            children: [
              Expanded(
                child: Text(
                  '${items.length} artículo(s)',
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
            ...items.map((i) => StockRow(
                  item: i,
                  onOrder: _onOrder[i.itemId] ?? 0,
                  committed: _committed[i.itemId] ?? 0,
                  price: _prices[i.itemId],
                  onTap: () => Navigator.of(context)
                      .push(
                        MaterialPageRoute(
                          builder: (_) => StockItemDetailView(
                            item: i,
                            price: _prices[i.itemId],
                            committed: _committed[i.itemId] ?? 0,
                          ),
                        ),
                      )
                      .then((_) => _load()),
                )),
        ],
      ),
      ),
    );
  }

  /// Chip de filtro con conteo: el número ES la información; sin resultados
  /// se muestra sin número (regla B.2).
  Widget _filterChip(_StockFilter value, String label) {
    final dpi = DpiScale.of(context);
    final selected = _filter == value;
    final count = value == _StockFilter.all ? null : _filterCount(value);
    final accent = value == _StockFilter.belowMin
        ? MangoThemeFactory.danger
        : MangoThemeFactory.mango;
    return Padding(
      padding: EdgeInsets.only(right: dpi.space(6)),
      child: ChoiceChip(
        label: Text(
            count != null && count > 0 ? '$label ($count)' : label),
        selected: selected,
        onSelected: (_) => setState(() => _filter = value),
        showCheckmark: false,
        visualDensity: VisualDensity.compact,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        selectedColor: accent.withValues(alpha: 0.2),
        labelStyle: TextStyle(
          color: selected ? accent : null,
          fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
          fontSize: dpi.font(12),
        ),
      ),
    );
  }
}
