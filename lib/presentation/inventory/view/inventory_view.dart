import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/formatters/mango_formatters.dart';
import '../../../core/responsive/dpi_scale.dart';
import '../../../domain/inventory/inventory_models.dart';
import '../../theme/theme_data_factory.dart';
import '../viewmodel/inventory_view_model.dart';
import 'shopping_list_view.dart';

/// Inventario maestro: lista de insumos con stock total, badge de estado
/// (verde / amarillo / rojo) y desglose por bodega al expandir.
///
/// Se mantiene en vivo vía suscripción realtime a `inventory_stock` con
/// debounce de 500ms (manejado en el viewmodel).
class InventoryView extends ConsumerStatefulWidget {
  const InventoryView({super.key});

  @override
  ConsumerState<InventoryView> createState() => _InventoryViewState();
}

enum _Filter { all, low, out }

class _InventoryViewState extends ConsumerState<InventoryView> {
  String _query = '';
  _Filter _filter = _Filter.all;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(inventoryViewModelProvider.notifier).load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final dpi = DpiScale.of(context);
    final state = ref.watch(inventoryViewModelProvider);

    final lowCount = state.items.where((i) => i.isLow || i.isOut).length;

    final filtered = state.items.where((item) {
      switch (_filter) {
        case _Filter.low:
          if (!(item.isLow || item.isOut)) return false;
          break;
        case _Filter.out:
          if (!item.isOut) return false;
          break;
        case _Filter.all:
          break;
      }
      if (_query.isEmpty) return true;
      final q = _query.toLowerCase();
      return item.name.toLowerCase().contains(q) ||
          (item.sku?.toLowerCase().contains(q) ?? false);
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Inventario'),
        centerTitle: false,
        actions: [
          if (lowCount > 0)
            Padding(
              padding: EdgeInsets.only(right: dpi.space(8)),
              child: IconButton(
                tooltip: 'Lista de compras',
                icon: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    const Icon(Icons.shopping_cart_outlined),
                    Positioned(
                      top: -4,
                      right: -4,
                      child: Container(
                        padding: const EdgeInsets.all(3),
                        decoration: const BoxDecoration(
                          color: MangoThemeFactory.danger,
                          shape: BoxShape.circle,
                        ),
                        constraints: const BoxConstraints(minWidth: 14, minHeight: 14),
                        child: Text(
                          '$lowCount',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                  ],
                ),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => ShoppingListView(
                      items: state.items.where((i) => i.isLow || i.isOut).toList(),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
      body: state.isLoading && state.items.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : state.error != null && state.items.isEmpty
              ? Center(
                  child: Padding(
                    padding: EdgeInsets.all(dpi.space(20)),
                    child: Text(
                      state.error!,
                      style: TextStyle(color: MangoThemeFactory.danger),
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: () => ref.read(inventoryViewModelProvider.notifier).load(),
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
                    padding: EdgeInsets.fromLTRB(dpi.space(16), dpi.space(12), dpi.space(16),
                        dpi.space(16) + MediaQuery.of(context).padding.bottom),
                    children: [
                      _Summary(items: state.items),
                      SizedBox(height: dpi.space(12)),
                      TextField(
                        onChanged: (v) => setState(() => _query = v),
                        decoration: InputDecoration(
                          hintText: 'Buscar insumo o SKU…',
                          prefixIcon: const Icon(Icons.search_rounded),
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(
                              horizontal: dpi.space(12), vertical: dpi.space(12)),
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(dpi.radius(12))),
                        ),
                      ),
                      SizedBox(height: dpi.space(10)),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            _FilterChip(label: 'Todos', selected: _filter == _Filter.all, onTap: () => setState(() => _filter = _Filter.all)),
                            SizedBox(width: dpi.space(6)),
                            _FilterChip(label: 'Stock bajo', selected: _filter == _Filter.low, onTap: () => setState(() => _filter = _Filter.low)),
                            SizedBox(width: dpi.space(6)),
                            _FilterChip(label: 'Agotados', selected: _filter == _Filter.out, onTap: () => setState(() => _filter = _Filter.out)),
                          ],
                        ),
                      ),
                      SizedBox(height: dpi.space(12)),
                      if (filtered.isEmpty)
                        Padding(
                          padding: EdgeInsets.symmetric(vertical: dpi.space(30)),
                          child: Center(
                            child: Text(
                              _query.isEmpty
                                  ? 'No hay insumos en este filtro.'
                                  : 'Sin resultados para "$_query".',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ),
                        )
                      else
                        ...filtered.map((item) => Padding(
                              padding: EdgeInsets.only(bottom: dpi.space(8)),
                              child: _InventoryTile(item: item),
                            )),
                    ],
                  ),
                ),
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({required this.items});
  final List<InventoryItemSnapshot> items;

  @override
  Widget build(BuildContext context) {
    final dpi = DpiScale.of(context);
    final total = items.length;
    final low = items.where((i) => i.isLow && !i.isOut).length;
    final out = items.where((i) => i.isOut).length;
    final ok = total - low - out;
    return Container(
      padding: EdgeInsets.all(dpi.space(16)),
      decoration: BoxDecoration(
        color: MangoThemeFactory.cardColor(context),
        borderRadius: BorderRadius.circular(dpi.radius(16)),
        border: Border.all(color: MangoThemeFactory.borderColor(context)),
      ),
      child: Row(
        children: [
          Expanded(
              child:
                  _statTile(context, 'Insumos', '$total', MangoThemeFactory.textColor(context))),
          _verticalDivider(dpi),
          Expanded(child: _statTile(context, 'OK', '$ok', MangoThemeFactory.success)),
          _verticalDivider(dpi),
          Expanded(child: _statTile(context, 'Bajo', '$low', MangoThemeFactory.warning)),
          _verticalDivider(dpi),
          Expanded(child: _statTile(context, 'Agotado', '$out', MangoThemeFactory.danger)),
        ],
      ),
    );
  }

  Widget _verticalDivider(DpiScale dpi) =>
      Container(width: 1, height: dpi.scale(28), color: Colors.black12);

  Widget _statTile(BuildContext context, String label, String value, Color color) {
    final dpi = DpiScale.of(context);
    return Column(
      children: [
        Text(label,
            style:
                TextStyle(fontSize: dpi.font(10), color: MangoThemeFactory.mutedText(context))),
        SizedBox(height: dpi.space(2)),
        Text(
          value,
          style: TextStyle(fontSize: dpi.font(16), fontWeight: FontWeight.w800, color: color),
        ),
      ],
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final dpi = DpiScale.of(context);
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
      showCheckmark: false,
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      selectedColor: MangoThemeFactory.mango.withValues(alpha: 0.2),
      labelStyle: TextStyle(
        color: selected ? MangoThemeFactory.mango : null,
        fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
        fontSize: dpi.font(12),
      ),
    );
  }
}

class _InventoryTile extends StatefulWidget {
  const _InventoryTile({required this.item});
  final InventoryItemSnapshot item;

  @override
  State<_InventoryTile> createState() => _InventoryTileState();
}

class _InventoryTileState extends State<_InventoryTile> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final dpi = DpiScale.of(context);
    final item = widget.item;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final (badgeColor, badgeLabel) = item.isOut
        ? (MangoThemeFactory.danger, 'Agotado')
        : item.isLow
            ? (MangoThemeFactory.warning, 'Bajo')
            : (MangoThemeFactory.success, 'OK');

    return InkWell(
      onTap: item.byWarehouse.length > 1 ? () => setState(() => _expanded = !_expanded) : null,
      borderRadius: BorderRadius.circular(dpi.radius(14)),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: EdgeInsets.all(dpi.space(14)),
        decoration: BoxDecoration(
          color: MangoThemeFactory.cardColor(context),
          borderRadius: BorderRadius.circular(dpi.radius(14)),
          border: Border.all(
            color: _expanded
                ? badgeColor.withValues(alpha: 0.45)
                : MangoThemeFactory.borderColor(context),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: dpi.scale(38),
                  height: dpi.scale(38),
                  decoration: BoxDecoration(
                    color: badgeColor.withValues(alpha: isDark ? 0.2 : 0.12),
                    borderRadius: BorderRadius.circular(dpi.radius(10)),
                  ),
                  child: Icon(Icons.inventory_2_rounded, color: badgeColor, size: dpi.icon(20)),
                ),
                SizedBox(width: dpi.space(12)),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.name,
                        style: Theme.of(context)
                            .textTheme
                            .titleSmall
                            ?.copyWith(fontWeight: FontWeight.w700),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      SizedBox(height: dpi.space(2)),
                      Text(
                        _subtitleFor(item),
                        style: TextStyle(
                            fontSize: dpi.font(11),
                            color: MangoThemeFactory.mutedText(context)),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                SizedBox(width: dpi.space(8)),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '${MangoFormatters.number(item.totalQuantity.round())} ${item.unit}',
                      style: TextStyle(
                        fontSize: dpi.font(14),
                        fontWeight: FontWeight.w800,
                        color: MangoThemeFactory.textColor(context),
                      ),
                    ),
                    SizedBox(height: dpi.space(3)),
                    Container(
                      padding: EdgeInsets.symmetric(
                          horizontal: dpi.space(6), vertical: dpi.space(2)),
                      decoration: BoxDecoration(
                        color: badgeColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(dpi.radius(4)),
                      ),
                      child: Text(
                        badgeLabel,
                        style: TextStyle(
                          fontSize: dpi.font(9),
                          fontWeight: FontWeight.w800,
                          color: badgeColor,
                        ),
                      ),
                    ),
                  ],
                ),
                if (item.byWarehouse.length > 1) ...[
                  SizedBox(width: dpi.space(4)),
                  AnimatedRotation(
                    turns: _expanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 180),
                    child: Icon(
                      Icons.expand_more_rounded,
                      size: dpi.icon(18),
                      color: MangoThemeFactory.mutedText(context),
                    ),
                  ),
                ],
              ],
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 180),
              alignment: Alignment.topLeft,
              child: !_expanded
                  ? const SizedBox.shrink()
                  : Padding(
                      padding: EdgeInsets.only(top: dpi.space(12)),
                      child: Container(
                        padding: EdgeInsets.all(dpi.space(10)),
                        decoration: BoxDecoration(
                          color: MangoThemeFactory.altSurface(context),
                          borderRadius: BorderRadius.circular(dpi.radius(10)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            for (var i = 0; i < item.byWarehouse.length; i++) ...[
                              Row(
                                children: [
                                  Icon(Icons.warehouse_rounded,
                                      size: dpi.icon(14),
                                      color: MangoThemeFactory.mutedText(context)),
                                  SizedBox(width: dpi.space(8)),
                                  Expanded(
                                    child: Text(
                                      item.byWarehouse[i].warehouseName,
                                      style: TextStyle(
                                        fontSize: dpi.font(12),
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                  Text(
                                    '${MangoFormatters.number(item.byWarehouse[i].quantity.round())} ${item.unit}',
                                    style: TextStyle(
                                      fontSize: dpi.font(12),
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                              if (i < item.byWarehouse.length - 1)
                                SizedBox(height: dpi.space(6)),
                            ],
                          ],
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  String _subtitleFor(InventoryItemSnapshot item) {
    final parts = <String>[];
    if (item.sku != null && item.sku!.isNotEmpty) parts.add('SKU ${item.sku!}');
    if (item.minStock > 0) {
      parts.add('mín ${MangoFormatters.number(item.minStock.round())}');
    }
    if (item.byWarehouse.length > 1) {
      parts.add('${item.byWarehouse.length} bodegas');
    }
    return parts.isEmpty ? item.unit : parts.join(' · ');
  }
}
