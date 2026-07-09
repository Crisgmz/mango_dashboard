import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/formatters/mango_formatters.dart';
import '../../../core/responsive/dpi_scale.dart';
import '../../../domain/catalog/admin_product.dart';
import '../../auth/viewmodel/auth_gate_view_model.dart';
import '../../theme/theme_data_factory.dart';
import '../viewmodel/products_admin_view_model.dart';

/// Pantalla para activar/desactivar productos (tabla `menu_items`).
class ProductsAdminView extends ConsumerStatefulWidget {
  const ProductsAdminView({super.key});

  @override
  ConsumerState<ProductsAdminView> createState() => _ProductsAdminViewState();
}

class _ProductsAdminViewState extends ConsumerState<ProductsAdminView> {
  String _query = '';

  String? get _businessId => ref.read(authGateViewModelProvider).profile?.businessId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final id = _businessId;
      if (id != null) ref.read(productsAdminViewModelProvider.notifier).load(id);
    });
  }

  Future<void> _refresh() async {
    final id = _businessId;
    if (id != null) await ref.read(productsAdminViewModelProvider.notifier).refresh(id);
  }

  @override
  Widget build(BuildContext context) {
    final dpi = DpiScale.of(context);
    final vm = ref.watch(productsAdminViewModelProvider);
    final id = _businessId;

    ref.listen<ProductsAdminState>(productsAdminViewModelProvider, (prev, next) {
      if (next.error != null && next.error != prev?.error) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(next.error!)));
      }
    });

    final filtered = _query.isEmpty
        ? vm.products
        : vm.products
            .where((p) => p.name.toLowerCase().contains(_query.toLowerCase()))
            .toList(growable: false);

    return Scaffold(
      appBar: AppBar(title: const Text('Productos')),
      body: id == null
          ? const Center(child: Text('No hay un negocio activo.'))
          : Column(
              children: [
                Padding(
                  padding: EdgeInsets.fromLTRB(dpi.space(16), dpi.space(12), dpi.space(16), dpi.space(4)),
                  child: TextField(
                    onChanged: (v) => setState(() => _query = v),
                    decoration: const InputDecoration(
                      hintText: 'Buscar producto…',
                      prefixIcon: Icon(Icons.search_rounded),
                    ),
                  ),
                ),
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: _refresh,
                    child: _body(context, dpi, vm, filtered),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _body(BuildContext context, DpiScale dpi, ProductsAdminState vm, List<AdminProduct> items) {
    if (vm.isLoading && vm.products.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (items.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          SizedBox(height: dpi.space(120)),
          Center(
            child: Text(
              vm.products.isEmpty ? 'No hay productos.' : 'Sin resultados.',
              style: TextStyle(color: MangoThemeFactory.mutedText(context)),
            ),
          ),
        ],
      );
    }

    // Agrupar por categoría preservando el orden alfabético ya aplicado.
    final groups = <String, List<AdminProduct>>{};
    for (final p in items) {
      (groups[p.categoryName ?? 'Sin categoría'] ??= []).add(p);
    }
    final groupNames = groups.keys.toList()..sort();

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.fromLTRB(dpi.space(16), dpi.space(8), dpi.space(16), dpi.space(28)),
      children: [
        for (final g in groupNames) ...[
          Padding(
            padding: EdgeInsets.symmetric(vertical: dpi.space(8)),
            child: Text(
              g,
              style: TextStyle(
                fontSize: dpi.font(12),
                fontWeight: FontWeight.w700,
                color: MangoThemeFactory.mutedText(context),
                letterSpacing: 0.4,
              ),
            ),
          ),
          ...groups[g]!.map((p) => _ProductRow(
                product: p,
                saving: vm.savingIds.contains(p.id),
                onChanged: (v) =>
                    ref.read(productsAdminViewModelProvider.notifier).toggle(p.id, v),
              )),
        ],
      ],
    );
  }
}

class _ProductRow extends StatelessWidget {
  const _ProductRow({required this.product, required this.saving, required this.onChanged});

  final AdminProduct product;
  final bool saving;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final dpi = DpiScale.of(context);
    return Container(
      margin: EdgeInsets.only(bottom: dpi.space(8)),
      padding: EdgeInsets.symmetric(horizontal: dpi.space(14), vertical: dpi.space(10)),
      decoration: BoxDecoration(
        color: MangoThemeFactory.cardColor(context),
        borderRadius: BorderRadius.circular(dpi.radius(14)),
        border: Border.all(color: MangoThemeFactory.borderColor(context)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  product.name,
                  style: TextStyle(
                    fontSize: dpi.font(14),
                    fontWeight: FontWeight.w600,
                    color: MangoThemeFactory.textColor(context),
                  ),
                ),
                SizedBox(height: dpi.space(2)),
                Text(
                  '${MangoFormatters.currency(product.price)} · ${product.isActive ? 'Disponible' : 'No disponible'}',
                  style: TextStyle(
                    fontSize: dpi.font(11.5),
                    color: product.isActive
                        ? MangoThemeFactory.mutedText(context)
                        : MangoThemeFactory.danger,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(width: dpi.space(8)),
          if (saving)
            SizedBox(
              width: dpi.icon(20),
              height: dpi.icon(20),
              child: const CircularProgressIndicator(strokeWidth: 2),
            )
          else
            Switch(
              value: product.isActive,
              activeThumbColor: MangoThemeFactory.success,
              onChanged: onChanged,
            ),
        ],
      ),
    );
  }
}
