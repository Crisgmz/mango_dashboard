import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/formatters/mango_formatters.dart';
import '../../../core/responsive/dpi_scale.dart';
import '../../auth/viewmodel/auth_gate_view_model.dart';
import '../../purchasing/view/purchase_orders_view.dart';
import '../../purchasing/view/reorder_suggestions_view.dart';
import '../../purchasing/view/suppliers_admin_view.dart';
import '../../theme/theme_data_factory.dart';
import '../viewmodel/inventory_hub_view_model.dart';
import 'counts_view.dart';
import 'stock_overview_view.dart';
import 'transfers_view.dart';

/// Pantalla A del PRD 6.2 — Hub de Inventario: tarjeta de valor a costo
/// arriba (con En orden / Bajo mínimo; Rotación queda oculta hasta tener
/// fuente de costo de venta) y lista de secciones con subtítulo dinámico y
/// contador. Una sección cuya fase no está desplegada NO se lista. El badge
/// NUEVO dura 30 días desde que la sección aparece por primera vez.
/// Content-only: vive en el tab 3 del bottom nav.
class InventoryHubView extends ConsumerStatefulWidget {
  const InventoryHubView({super.key});

  @override
  ConsumerState<InventoryHubView> createState() => _InventoryHubViewState();
}

class _InventoryHubViewState extends ConsumerState<InventoryHubView> {
  Map<String, bool> _isNew = const {};

  String? get _businessId =>
      ref.read(authGateViewModelProvider).profile?.businessId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _init());
  }

  Future<void> _init() async {
    final businessId = _businessId;
    if (businessId != null) {
      ref.read(inventoryHubViewModelProvider.notifier).load(businessId);
    }
    // Badge NUEVO: 30 días desde la primera vez que la sección se listó.
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now();
    final result = <String, bool>{};
    for (final key in [
      'counts',
      'purchases',
      'suppliers',
      'reorder',
      'transfers',
    ]) {
      final storedKey = 'hub_section_first_seen_$key';
      final stored = prefs.getString(storedKey);
      DateTime firstSeen;
      if (stored == null) {
        firstSeen = now;
        await prefs.setString(storedKey, now.toIso8601String());
      } else {
        firstSeen = DateTime.tryParse(stored) ?? now;
      }
      result[key] = now.difference(firstSeen) < const Duration(days: 30);
    }
    if (mounted) setState(() => _isNew = result);
  }

  Future<void> _refresh() async {
    final businessId = _businessId;
    if (businessId != null) {
      await ref.read(inventoryHubViewModelProvider.notifier).load(businessId);
    }
  }

  void _push(Widget page) {
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => page))
        .then((_) => _refresh());
  }

  @override
  Widget build(BuildContext context) {
    final dpi = DpiScale.of(context);
    final hub = ref.watch(inventoryHubViewModelProvider);
    final profile = ref.watch(authGateViewModelProvider).profile;
    final subtitle = [
      if (profile?.businessName != null) profile!.businessName!,
      if (profile?.branchName?.trim().isNotEmpty == true)
        profile!.branchName!.trim(),
    ].join(' · ');

    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(
            parent: BouncingScrollPhysics()),
        padding: EdgeInsets.fromLTRB(
            dpi.space(18), dpi.space(14), dpi.space(18), dpi.space(28)),
        children: [
          // ── Cabecera ──
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Inventario',
                        style: Theme.of(context).textTheme.headlineMedium),
                    if (subtitle.isNotEmpty) ...[
                      SizedBox(height: dpi.space(2)),
                      Text(subtitle,
                          style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ],
                ),
              ),
              IconButton.filledTonal(
                tooltip: 'Menú',
                onPressed: () => Scaffold.maybeOf(context)?.openDrawer(),
                icon: const Icon(Icons.tune_rounded),
                style: IconButton.styleFrom(
                  backgroundColor:
                      MangoThemeFactory.mango.withValues(alpha: 0.12),
                  foregroundColor: MangoThemeFactory.mango,
                ),
              ),
            ],
          ),
          SizedBox(height: dpi.space(16)),

          // ── Tarjeta de valor ──
          Container(
            padding: EdgeInsets.all(dpi.space(18)),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [MangoThemeFactory.mango, MangoThemeFactory.mangoDeep],
              ),
              borderRadius: BorderRadius.circular(dpi.radius(22)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'VALOR A COSTO',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: dpi.font(10.5),
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8,
                  ),
                ),
                SizedBox(height: dpi.space(4)),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    hub.stockValue != null
                        ? MangoFormatters.currency(hub.stockValue!)
                        : '—',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: dpi.font(30),
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                SizedBox(height: dpi.space(14)),
                Row(
                  children: [
                    Expanded(
                      child: _HeaderPill(
                        label: 'EN ORDEN',
                        // Cero se muestra como RD$0, no se oculta (regla A.1).
                        value: hub.onOrderValue != null
                            ? MangoFormatters.currency(hub.onOrderValue!)
                            : '—',
                      ),
                    ),
                    SizedBox(width: dpi.space(8)),
                    Expanded(
                      child: _HeaderPill(
                        label: 'BAJO MÍNIMO',
                        value: hub.lowCount?.toString() ?? '—',
                      ),
                    ),
                    // ROTACIÓN: oculta hasta tener costo de venta de 90 días.
                  ],
                ),
              ],
            ),
          ),
          SizedBox(height: dpi.space(16)),

          // ── Secciones ──
          Container(
            decoration: BoxDecoration(
              color: MangoThemeFactory.cardColor(context),
              borderRadius: BorderRadius.circular(dpi.radius(20)),
              border: Border.all(color: MangoThemeFactory.borderColor(context)),
            ),
            child: Column(
              children: [
                _SectionRow(
                  icon: Icons.account_tree_outlined,
                  title: 'Vista de stock',
                  subtitle: hub.itemCount != null
                      ? '${hub.itemCount} artículos'
                          '${(hub.lowCount ?? 0) > 0 ? ' · ${hub.lowCount} bajo mínimo' : ''}'
                      : 'Existencias y recepción',
                  counter: hub.lowCount,
                  counterColor: MangoThemeFactory.danger,
                  onTap: () => _push(const StockOverviewView()),
                ),
                _divider(context),
                _SectionRow(
                  icon: Icons.swap_vert_rounded,
                  title: 'Conteos de stock',
                  isNew: _isNew['counts'] ?? false,
                  subtitle: hub.lastCountAt != null
                      ? 'Último ${MangoFormatters.date(hub.lastCountAt!)}'
                          '${hub.lastCountStatus == 'in_progress' ? ' · en curso' : ''}'
                      : 'Audita tu stock físico',
                  onTap: () => _push(const CountsView()),
                ),
                _divider(context),
                _SectionRow(
                  icon: Icons.inventory_outlined,
                  title: 'Órdenes de compra',
                  isNew: _isNew['purchases'] ?? false,
                  subtitle: hub.openPoCount != null
                      ? '${hub.openPoCount} abiertas'
                          '${(hub.receivedTodayCount ?? 0) > 0 ? ' · ${hub.receivedTodayCount} llegó hoy' : ''}'
                      : 'Pide y recibe mercancía',
                  counter: hub.openPoCount,
                  counterColor: MangoThemeFactory.mango,
                  onTap: () => _push(const PurchaseOrdersView()),
                ),
                _divider(context),
                _SectionRow(
                  icon: Icons.shopping_basket_outlined,
                  title: 'Qué comprar hoy',
                  isNew: _isNew['reorder'] ?? false,
                  subtitle: 'Sugerido por cobertura',
                  counter: hub.suggestionsCount,
                  counterColor: MangoThemeFactory.mango,
                  onTap: () => _push(const ReorderSuggestionsView()),
                ),
                _divider(context),
                _SectionRow(
                  icon: Icons.swap_horiz_rounded,
                  title: 'Transferencias',
                  isNew: _isNew['transfers'] ?? false,
                  subtitle: 'Mueve stock entre bodegas',
                  counter: hub.pendingTransfers,
                  counterColor: MangoThemeFactory.warning,
                  onTap: () => _push(const TransfersView()),
                ),
                _divider(context),
                _SectionRow(
                  icon: Icons.storefront_outlined,
                  title: 'Suplidores',
                  isNew: _isNew['suppliers'] ?? false,
                  subtitle: hub.activeSuppliers != null
                      ? '${hub.activeSuppliers} activos'
                      : 'Proveedores y RNC para el 606',
                  onTap: () => _push(const SuppliersAdminView()),
                ),
                // Qué comprar hoy · Transferencias · Métricas: se listan
                // cuando su fase esté desplegada (regla A.2 — sin filas
                // muertas).
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _divider(BuildContext context) => Divider(
        height: 1,
        indent: DpiScale.of(context).space(56),
        color: MangoThemeFactory.borderColor(context).withValues(alpha: 0.6),
      );
}

class _HeaderPill extends StatelessWidget {
  const _HeaderPill({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final dpi = DpiScale.of(context);
    return Container(
      padding: EdgeInsets.symmetric(
          horizontal: dpi.space(12), vertical: dpi.space(8)),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(dpi.radius(12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: Colors.white70,
              fontSize: dpi.font(9),
              fontWeight: FontWeight.w800,
              letterSpacing: 0.6,
            ),
          ),
          SizedBox(height: dpi.space(2)),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              style: TextStyle(
                color: Colors.white,
                fontSize: dpi.font(14),
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionRow extends StatelessWidget {
  const _SectionRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.counter,
    this.counterColor,
    this.isNew = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  /// Solo se muestra con valor mayor que cero (regla A.2).
  final int? counter;
  final Color? counterColor;
  final bool isNew;

  @override
  Widget build(BuildContext context) {
    final dpi = DpiScale.of(context);
    final showCounter = counter != null && counter! > 0;
    final cColor = counterColor ?? MangoThemeFactory.mango;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.symmetric(
              horizontal: dpi.space(16), vertical: dpi.space(14)),
          child: Row(
            children: [
              Icon(icon,
                  size: dpi.icon(22),
                  color: MangoThemeFactory.textColor(context)
                      .withValues(alpha: 0.75)),
              SizedBox(width: dpi.space(14)),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            title,
                            style: TextStyle(
                              fontSize: dpi.font(15),
                              fontWeight: FontWeight.w700,
                              color: MangoThemeFactory.textColor(context),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (isNew) ...[
                          SizedBox(width: dpi.space(6)),
                          Container(
                            padding: EdgeInsets.symmetric(
                                horizontal: dpi.space(6),
                                vertical: dpi.space(2)),
                            decoration: BoxDecoration(
                              color: MangoThemeFactory.mango
                                  .withValues(alpha: 0.14),
                              borderRadius:
                                  BorderRadius.circular(dpi.radius(6)),
                            ),
                            child: Text(
                              'NUEVO',
                              style: TextStyle(
                                fontSize: dpi.font(8.5),
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.4,
                                color: MangoThemeFactory.mango,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    SizedBox(height: dpi.space(2)),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: dpi.font(12),
                        color: MangoThemeFactory.mutedText(context),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (showCounter) ...[
                SizedBox(width: dpi.space(8)),
                Container(
                  padding: EdgeInsets.symmetric(
                      horizontal: dpi.space(9), vertical: dpi.space(4)),
                  decoration: BoxDecoration(
                    color: cColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(dpi.radius(10)),
                  ),
                  child: Text(
                    '$counter',
                    style: TextStyle(
                      fontSize: dpi.font(13),
                      fontWeight: FontWeight.w800,
                      color: cColor,
                    ),
                  ),
                ),
              ],
              SizedBox(width: dpi.space(6)),
              Icon(Icons.chevron_right_rounded,
                  size: dpi.icon(20),
                  color: MangoThemeFactory.mutedText(context)),
            ],
          ),
        ),
      ),
    );
  }
}
