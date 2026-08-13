import 'package:flutter/material.dart';

import '../../core/responsive/dpi_scale.dart';
import '../../domain/inventory/inventory_models.dart';
import '../theme/theme_data_factory.dart';

/// Selector de insumos en bottom sheet con el lenguaje visual del app:
/// fondo del scaffold, esquinas superiores redondeadas, asa de arrastre,
/// búsqueda y cada resultado como card blanda. Devuelve el ítem elegido.
Future<InventoryItemSnapshot?> showSoftItemPicker({
  required BuildContext context,
  required List<InventoryItemSnapshot> items,
  required String Function(InventoryItemSnapshot) subtitleOf,
  String hint = 'Buscar insumo…',
}) {
  return showModalBottomSheet<InventoryItemSnapshot>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) =>
        _SoftItemPickerSheet(items: items, subtitleOf: subtitleOf, hint: hint),
  );
}

class _SoftItemPickerSheet extends StatefulWidget {
  const _SoftItemPickerSheet({
    required this.items,
    required this.subtitleOf,
    required this.hint,
  });

  final List<InventoryItemSnapshot> items;
  final String Function(InventoryItemSnapshot) subtitleOf;
  final String hint;

  @override
  State<_SoftItemPickerSheet> createState() => _SoftItemPickerSheetState();
}

class _SoftItemPickerSheetState extends State<_SoftItemPickerSheet> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final dpi = DpiScale.of(context);
    final filtered = _query.isEmpty
        ? widget.items
        : widget.items
            .where((i) =>
                i.name.toLowerCase().contains(_query.toLowerCase()) ||
                (i.sku?.toLowerCase().contains(_query.toLowerCase()) ?? false))
            .toList(growable: false);

    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        height: MediaQuery.of(context).size.height * 0.72,
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(dpi.radius(24))),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            children: [
              SizedBox(height: dpi.space(10)),
              Container(
                width: dpi.scale(42),
                height: dpi.scale(4),
                decoration: BoxDecoration(
                  color: MangoThemeFactory.borderColor(context),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              Padding(
                padding: EdgeInsets.all(dpi.space(14)),
                child: TextField(
                  autofocus: true,
                  onChanged: (v) => setState(() => _query = v),
                  decoration: InputDecoration(
                    hintText: widget.hint,
                    prefixIcon: const Icon(Icons.search_rounded),
                    isDense: true,
                  ),
                ),
              ),
              Expanded(
                child: filtered.isEmpty
                    ? Center(
                        child: Text(
                          'Sin resultados.',
                          style: TextStyle(
                              color: MangoThemeFactory.mutedText(context)),
                        ),
                      )
                    : ListView.builder(
                        padding: EdgeInsets.fromLTRB(dpi.space(14), 0,
                            dpi.space(14), dpi.space(16)),
                        itemCount: filtered.length,
                        itemBuilder: (context, index) {
                          final item = filtered[index];
                          return Container(
                            margin: EdgeInsets.only(bottom: dpi.space(8)),
                            decoration: BoxDecoration(
                              color: MangoThemeFactory.cardColor(context),
                              borderRadius:
                                  BorderRadius.circular(dpi.radius(14)),
                              border: Border.all(
                                  color:
                                      MangoThemeFactory.borderColor(context)),
                            ),
                            child: Material(
                              color: Colors.transparent,
                              child: InkWell(
                                onTap: () =>
                                    Navigator.of(context).pop(item),
                                borderRadius:
                                    BorderRadius.circular(dpi.radius(14)),
                                child: Padding(
                                  padding: EdgeInsets.symmetric(
                                      horizontal: dpi.space(14),
                                      vertical: dpi.space(12)),
                                  child: Row(
                                    children: [
                                      Container(
                                        width: dpi.scale(36),
                                        height: dpi.scale(36),
                                        alignment: Alignment.center,
                                        decoration: BoxDecoration(
                                          color: MangoThemeFactory.mango
                                              .withValues(alpha: 0.1),
                                          borderRadius: BorderRadius.circular(
                                              dpi.radius(10)),
                                        ),
                                        child: Text(
                                          item.name.isNotEmpty
                                              ? item.name[0].toUpperCase()
                                              : '?',
                                          style: TextStyle(
                                            fontSize: dpi.font(14),
                                            fontWeight: FontWeight.w800,
                                            color: MangoThemeFactory.mango,
                                          ),
                                        ),
                                      ),
                                      SizedBox(width: dpi.space(12)),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              item.name,
                                              style: TextStyle(
                                                fontSize: dpi.font(13.5),
                                                fontWeight: FontWeight.w700,
                                                color: MangoThemeFactory
                                                    .textColor(context),
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                            SizedBox(height: dpi.space(2)),
                                            Text(
                                              widget.subtitleOf(item),
                                              style: TextStyle(
                                                fontSize: dpi.font(11),
                                                color: MangoThemeFactory
                                                    .mutedText(context),
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ],
                                        ),
                                      ),
                                      Icon(Icons.add_circle_outline_rounded,
                                          size: dpi.icon(20),
                                          color: MangoThemeFactory.mango),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
