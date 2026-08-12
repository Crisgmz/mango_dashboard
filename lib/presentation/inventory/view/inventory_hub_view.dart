import 'package:flutter/material.dart';

import '../../../core/responsive/dpi_scale.dart';
import '../../purchasing/view/purchase_orders_view.dart';
import '../../theme/theme_data_factory.dart';
import 'stock_overview_view.dart';

/// Hub de Inventario al estilo Square for Retail: una pestaña del bottom nav
/// con secciones internas — Stock (overview con recepción), Catálogo (los
/// artículos de venta) y Compras (OCs + suplidores). Content-only: vive
/// dentro del IndexedStack del root. Conteos, Transferencias y Métricas se
/// suman aquí cuando se construyan (F5+).
class InventoryHubView extends StatefulWidget {
  const InventoryHubView({super.key, required this.catalog});

  /// La sección de catálogo (el ItemsView existente), construida por el root
  /// porque necesita su dataState/onRefresh.
  final Widget catalog;

  @override
  State<InventoryHubView> createState() => _InventoryHubViewState();
}

class _InventoryHubViewState extends State<InventoryHubView> {
  int _section = 0;

  static const _sections = [
    (icon: Icons.account_tree_outlined, label: 'Stock'),
    (icon: Icons.fastfood_outlined, label: 'Catálogo'),
    (icon: Icons.shopping_cart_checkout_outlined, label: 'Compras'),
  ];

  @override
  Widget build(BuildContext context) {
    final dpi = DpiScale.of(context);
    return Column(
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(
              dpi.space(18), dpi.space(14), dpi.space(18), dpi.space(10)),
          child: Row(
            children: [
              Expanded(
                child: Text('Inventario',
                    style: Theme.of(context).textTheme.headlineMedium),
              ),
            ],
          ),
        ),
        // Selector de sección (el "sidebar" de Square, horizontal en móvil).
        SizedBox(
          height: dpi.scale(40),
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            padding: EdgeInsets.symmetric(horizontal: dpi.space(16)),
            itemCount: _sections.length,
            separatorBuilder: (_, _) => SizedBox(width: dpi.space(8)),
            itemBuilder: (context, index) {
              final s = _sections[index];
              final selected = _section == index;
              return InkWell(
                onTap: () => setState(() => _section = index),
                borderRadius: BorderRadius.circular(dpi.radius(12)),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: EdgeInsets.symmetric(horizontal: dpi.space(14)),
                  decoration: BoxDecoration(
                    color: selected
                        ? MangoThemeFactory.mango.withValues(alpha: 0.14)
                        : MangoThemeFactory.cardColor(context),
                    borderRadius: BorderRadius.circular(dpi.radius(12)),
                    border: Border.all(
                      color: selected
                          ? MangoThemeFactory.mango.withValues(alpha: 0.5)
                          : MangoThemeFactory.borderColor(context),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        s.icon,
                        size: dpi.icon(16),
                        color: selected
                            ? MangoThemeFactory.mango
                            : MangoThemeFactory.mutedText(context),
                      ),
                      SizedBox(width: dpi.space(6)),
                      Text(
                        s.label,
                        style: TextStyle(
                          fontSize: dpi.font(12.5),
                          fontWeight:
                              selected ? FontWeight.w800 : FontWeight.w600,
                          color: selected
                              ? MangoThemeFactory.mango
                              : MangoThemeFactory.mutedText(context),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        SizedBox(height: dpi.space(4)),
        Expanded(
          child: IndexedStack(
            index: _section,
            children: [
              const StockOverviewView(),
              widget.catalog,
              const PurchaseOrdersView(embedded: true),
            ],
          ),
        ),
      ],
    );
  }
}
