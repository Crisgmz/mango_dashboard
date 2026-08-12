import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/formatters/mango_formatters.dart';
import '../../../core/responsive/dpi_scale.dart';
import '../../../domain/purchasing/purchase_order.dart';
import '../../auth/viewmodel/auth_gate_view_model.dart';
import '../../theme/theme_data_factory.dart';
import '../viewmodel/purchase_orders_view_model.dart';
import 'purchase_order_detail_view.dart';
import 'purchase_order_form_view.dart';
import 'suppliers_admin_view.dart';

/// Módulo de compras (PRD 6.1 F2): lista de órdenes de compra con resumen,
/// filtro por estado, creación de OC y acceso a suplidores.
class PurchaseOrdersView extends ConsumerStatefulWidget {
  const PurchaseOrdersView({super.key, this.embedded = false});

  /// True cuando vive como sección del hub de Inventario: sin Scaffold ni
  /// AppBar propios; las acciones (nueva orden, suplidores) van inline.
  final bool embedded;

  @override
  ConsumerState<PurchaseOrdersView> createState() => _PurchaseOrdersViewState();
}

class _PurchaseOrdersViewState extends ConsumerState<PurchaseOrdersView> {
  String _statusFilter = 'open';

  String? get _businessId =>
      ref.read(authGateViewModelProvider).profile?.businessId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final id = _businessId;
      if (id != null) {
        ref.read(purchaseOrdersViewModelProvider.notifier).load(id);
      }
    });
  }

  Future<void> _refresh() async {
    final id = _businessId;
    if (id != null) {
      await ref.read(purchaseOrdersViewModelProvider.notifier).refresh(id);
    }
  }

  List<PurchaseOrder> _filtered(List<PurchaseOrder> orders) {
    switch (_statusFilter) {
      case 'open':
        return orders.where((o) => o.isOpen).toList(growable: false);
      case 'all':
        return orders;
      default:
        return orders
            .where((o) => o.status == _statusFilter)
            .toList(growable: false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dpi = DpiScale.of(context);
    final vm = ref.watch(purchaseOrdersViewModelProvider);
    final id = _businessId;

    ref.listen<PurchaseOrdersState>(purchaseOrdersViewModelProvider,
        (prev, next) {
      if (next.error != null && next.error != prev?.error) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(next.error!)));
      }
    });

    final orders = _filtered(vm.orders);

    final content = id == null
        ? const Center(child: Text('No hay un negocio activo.'))
        : RefreshIndicator(
            onRefresh: _refresh,
            child: vm.isLoading && vm.orders.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : ListView(
                    physics: const AlwaysScrollableScrollPhysics(
                        parent: BouncingScrollPhysics()),
                    padding: EdgeInsets.fromLTRB(dpi.space(16), dpi.space(12),
                        dpi.space(16), dpi.space(96)),
                    children: [
                      if (widget.embedded) ...[
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () => Navigator.of(context).push(
                                  MaterialPageRoute(
                                      builder: (_) =>
                                          const SuppliersAdminView()),
                                ),
                                style: OutlinedButton.styleFrom(
                                  padding: EdgeInsets.symmetric(
                                      vertical: dpi.space(12)),
                                ),
                                icon: Icon(Icons.local_shipping_outlined,
                                    size: dpi.icon(16)),
                                label: const Text('Suplidores'),
                              ),
                            ),
                            SizedBox(width: dpi.space(10)),
                            Expanded(
                              flex: 2,
                              child: FilledButton.icon(
                                onPressed: () async {
                                  await Navigator.of(context).push(
                                    MaterialPageRoute(
                                        builder: (_) =>
                                            const PurchaseOrderFormView()),
                                  );
                                  _refresh();
                                },
                                style: FilledButton.styleFrom(
                                  backgroundColor: MangoThemeFactory.mango,
                                  padding: EdgeInsets.symmetric(
                                      vertical: dpi.space(12)),
                                ),
                                icon: const Icon(Icons.add_rounded, size: 18),
                                label: const Text('Nueva orden'),
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: dpi.space(12)),
                      ],
                      _SummaryHeader(orders: vm.orders),
                        SizedBox(height: dpi.space(14)),
                        SizedBox(
                          height: dpi.scale(34),
                          child: ListView(
                            scrollDirection: Axis.horizontal,
                            physics: const BouncingScrollPhysics(),
                            children: [
                              _chip('open', 'Abiertas'),
                              _chip('all', 'Todas'),
                              _chip('draft', 'Borrador'),
                              _chip('sent', 'Enviadas'),
                              _chip('partial', 'Parciales'),
                              _chip('received', 'Recibidas'),
                              _chip('cancelled', 'Canceladas'),
                            ],
                          ),
                        ),
                        SizedBox(height: dpi.space(12)),
                        if (orders.isEmpty)
                          _EmptyState(
                            message: vm.orders.isEmpty
                                ? 'Aún no hay órdenes de compra.\nCrea la primera con el botón +.'
                                : 'Sin órdenes en este filtro.',
                          )
                        else
                          ...orders.map((o) => _OrderCard(
                                order: o,
                                onTap: () async {
                                  await Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) => PurchaseOrderDetailView(
                                          orderId: o.id),
                                    ),
                                  );
                                  _refresh();
                                },
                              )),
                    ],
                  ),
          );

    if (widget.embedded) return content;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Compras'),
        centerTitle: false,
        actions: [
          IconButton(
            tooltip: 'Suplidores',
            icon: const Icon(Icons.local_shipping_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SuppliersAdminView()),
            ),
          ),
        ],
      ),
      floatingActionButton: id == null || widget.embedded
          ? null
          : FloatingActionButton.extended(
              onPressed: () async {
                await Navigator.of(context).push(
                  MaterialPageRoute(
                      builder: (_) => const PurchaseOrderFormView()),
                );
                _refresh();
              },
              backgroundColor: MangoThemeFactory.mango,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Nueva orden'),
            ),
      body: content,
    );
  }

  Widget _chip(String value, String label) {
    final dpi = DpiScale.of(context);
    final selected = _statusFilter == value;
    return Padding(
      padding: EdgeInsets.only(right: dpi.space(6)),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => setState(() => _statusFilter = value),
        showCheckmark: false,
        visualDensity: VisualDensity.compact,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        selectedColor: MangoThemeFactory.mango.withValues(alpha: 0.2),
        labelStyle: TextStyle(
          color: selected ? MangoThemeFactory.mango : null,
          fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
          fontSize: dpi.font(12),
        ),
      ),
    );
  }
}

Color statusColor(String status) {
  switch (status) {
    case 'draft':
      return MangoThemeFactory.info;
    case 'sent':
      return MangoThemeFactory.warning;
    case 'partial':
      return MangoThemeFactory.mango;
    case 'received':
      return MangoThemeFactory.success;
    case 'cancelled':
      return MangoThemeFactory.danger;
    default:
      return MangoThemeFactory.info;
  }
}

/// Header con gradiente al estilo del dashboard: monto abierto + conteos.
class _SummaryHeader extends StatelessWidget {
  const _SummaryHeader({required this.orders});

  final List<PurchaseOrder> orders;

  @override
  Widget build(BuildContext context) {
    final dpi = DpiScale.of(context);
    final open = orders.where((o) => o.isOpen).toList(growable: false);
    final openAmount = open.fold<double>(0, (sum, o) => sum + o.total);
    final toReceive =
        open.where((o) => o.status != 'draft').length;
    final received = orders.where((o) => o.status == 'received').length;

    return Container(
      padding: EdgeInsets.all(dpi.space(18)),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            MangoThemeFactory.mango,
            MangoThemeFactory.mangoDeep,
          ],
        ),
        borderRadius: BorderRadius.circular(dpi.radius(20)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.shopping_cart_checkout_rounded,
                  color: Colors.white, size: dpi.icon(18)),
              SizedBox(width: dpi.space(6)),
              Text(
                'Compras en curso',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: dpi.font(12),
                    fontWeight: FontWeight.w600),
              ),
            ],
          ),
          SizedBox(height: dpi.space(10)),
          Text('Monto abierto',
              style:
                  TextStyle(color: Colors.white70, fontSize: dpi.font(11))),
          SizedBox(height: dpi.space(2)),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              MangoFormatters.currency(openAmount),
              style: TextStyle(
                  color: Colors.white,
                  fontSize: dpi.font(24),
                  fontWeight: FontWeight.w800),
            ),
          ),
          SizedBox(height: dpi.space(10)),
          Row(
            children: [
              Expanded(
                  child: _MiniStat(label: 'Abiertas', value: '${open.length}')),
              _divider(dpi),
              Expanded(
                  child:
                      _MiniStat(label: 'Por recibir', value: '$toReceive')),
              _divider(dpi),
              Expanded(
                  child: _MiniStat(label: 'Recibidas', value: '$received')),
            ],
          ),
        ],
      ),
    );
  }

  Widget _divider(DpiScale dpi) => Container(
        width: 1,
        height: dpi.scale(26),
        color: Colors.white.withValues(alpha: 0.22),
      );
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final dpi = DpiScale.of(context);
    return Column(
      children: [
        Text(value,
            style: TextStyle(
                color: Colors.white,
                fontSize: dpi.font(16),
                fontWeight: FontWeight.w800)),
        SizedBox(height: dpi.space(2)),
        Text(label,
            style: TextStyle(color: Colors.white70, fontSize: dpi.font(10))),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    final dpi = DpiScale.of(context);
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(dpi.space(28)),
      decoration: BoxDecoration(
        color: MangoThemeFactory.cardColor(context),
        borderRadius: BorderRadius.circular(dpi.radius(20)),
        border: Border.all(color: MangoThemeFactory.borderColor(context)),
      ),
      child: Column(
        children: [
          Icon(Icons.receipt_long_rounded,
              size: dpi.icon(42),
              color: MangoThemeFactory.mutedText(context)
                  .withValues(alpha: 0.6)),
          SizedBox(height: dpi.space(10)),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(color: MangoThemeFactory.mutedText(context)),
          ),
        ],
      ),
    );
  }
}

class _OrderCard extends StatelessWidget {
  const _OrderCard({required this.order, required this.onTap});

  final PurchaseOrder order;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final dpi = DpiScale.of(context);
    final color = statusColor(order.status);
    final now = DateTime.now();
    final overdue = order.isOpen &&
        order.status != 'draft' &&
        order.expectedDate != null &&
        order.expectedDate!
            .isBefore(DateTime(now.year, now.month, now.day));

    return Container(
      margin: EdgeInsets.only(bottom: dpi.space(10)),
      decoration: BoxDecoration(
        color: MangoThemeFactory.cardColor(context),
        borderRadius: BorderRadius.circular(dpi.radius(16)),
        border: Border.all(
          color: overdue
              ? MangoThemeFactory.danger.withValues(alpha: 0.45)
              : MangoThemeFactory.borderColor(context),
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(dpi.radius(16)),
          child: Padding(
            padding: EdgeInsets.all(dpi.space(14)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: dpi.scale(40),
                      height: dpi.scale(40),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(dpi.radius(12)),
                      ),
                      child: Icon(Icons.receipt_long_rounded,
                          color: color, size: dpi.icon(20)),
                    ),
                    SizedBox(width: dpi.space(12)),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            order.supplierName ?? 'Sin suplidor',
                            style: TextStyle(
                              fontSize: dpi.font(14),
                              fontWeight: FontWeight.w700,
                              color: MangoThemeFactory.textColor(context),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          SizedBox(height: dpi.space(2)),
                          Text(
                            order.orderNumber,
                            style: TextStyle(
                              fontSize: dpi.font(11),
                              fontWeight: FontWeight.w600,
                              fontFamily: 'monospace',
                              color: MangoThemeFactory.mutedText(context),
                            ),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(width: dpi.space(8)),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          MangoFormatters.currency(order.total),
                          style: TextStyle(
                            fontSize: dpi.font(14.5),
                            fontWeight: FontWeight.w800,
                            color: MangoThemeFactory.textColor(context),
                          ),
                        ),
                        SizedBox(height: dpi.space(4)),
                        Container(
                          padding: EdgeInsets.symmetric(
                              horizontal: dpi.space(7),
                              vertical: dpi.space(2)),
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.12),
                            borderRadius:
                                BorderRadius.circular(dpi.radius(6)),
                          ),
                          child: Text(
                            order.statusLabel.toUpperCase(),
                            style: TextStyle(
                              fontSize: dpi.font(9),
                              fontWeight: FontWeight.w800,
                              color: color,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                SizedBox(height: dpi.space(10)),
                Row(
                  children: [
                    Icon(Icons.schedule_rounded,
                        size: dpi.icon(12),
                        color: overdue
                            ? MangoThemeFactory.danger
                            : MangoThemeFactory.mutedText(context)),
                    SizedBox(width: dpi.space(4)),
                    Text(
                      order.expectedDate != null
                          ? (overdue
                              ? 'Atrasada · esperada ${MangoFormatters.date(order.expectedDate!)}'
                              : 'Esperada ${MangoFormatters.date(order.expectedDate!)}')
                          : (order.createdAt != null
                              ? 'Creada ${MangoFormatters.date(order.createdAt!)}'
                              : ''),
                      style: TextStyle(
                        fontSize: dpi.font(11),
                        fontWeight:
                            overdue ? FontWeight.w700 : FontWeight.w500,
                        color: overdue
                            ? MangoThemeFactory.danger
                            : MangoThemeFactory.mutedText(context),
                      ),
                    ),
                    const Spacer(),
                    Icon(Icons.chevron_right_rounded,
                        size: dpi.icon(18),
                        color: MangoThemeFactory.mutedText(context)),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
