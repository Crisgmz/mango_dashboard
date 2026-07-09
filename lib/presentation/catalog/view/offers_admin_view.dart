import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/formatters/mango_formatters.dart';
import '../../../core/responsive/dpi_scale.dart';
import '../../../domain/catalog/promotion.dart';
import '../../auth/viewmodel/auth_gate_view_model.dart';
import '../../theme/theme_data_factory.dart';
import '../viewmodel/offers_admin_view_model.dart';
import 'promotion_form_view.dart';

/// Pantalla de ofertas: listar, crear, editar, activar/desactivar y eliminar.
class OffersAdminView extends ConsumerStatefulWidget {
  const OffersAdminView({super.key});

  @override
  ConsumerState<OffersAdminView> createState() => _OffersAdminViewState();
}

class _OffersAdminViewState extends ConsumerState<OffersAdminView> {
  String? get _businessId => ref.read(authGateViewModelProvider).profile?.businessId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final id = _businessId;
      if (id != null) ref.read(offersAdminViewModelProvider.notifier).load(id);
    });
  }

  Future<void> _refresh() async {
    final id = _businessId;
    if (id != null) await ref.read(offersAdminViewModelProvider.notifier).load(id);
  }

  void _openForm({Promotion? existing}) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => PromotionFormView(existing: existing)),
    );
  }

  Future<void> _confirmDelete(Promotion p) async {
    final id = _businessId;
    if (id == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar oferta'),
        content: Text('¿Eliminar "${p.name}"? Esta acción no se puede deshacer.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: MangoThemeFactory.danger),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final error = await ref.read(offersAdminViewModelProvider.notifier).delete(id, p.id);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(error ?? 'Oferta eliminada.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dpi = DpiScale.of(context);
    final vm = ref.watch(offersAdminViewModelProvider);
    final id = _businessId;

    ref.listen<OffersAdminState>(offersAdminViewModelProvider, (prev, next) {
      if (next.error != null && next.error != prev?.error) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(next.error!)));
      }
    });

    return Scaffold(
      appBar: AppBar(title: const Text('Ofertas')),
      floatingActionButton: id == null
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _openForm(),
              backgroundColor: MangoThemeFactory.mango,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Nueva oferta'),
            ),
      body: id == null
          ? const Center(child: Text('No hay un negocio activo.'))
          : RefreshIndicator(onRefresh: _refresh, child: _body(context, dpi, vm)),
    );
  }

  Widget _body(BuildContext context, DpiScale dpi, OffersAdminState vm) {
    if (vm.isLoading && vm.promotions.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (vm.promotions.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          SizedBox(height: dpi.space(110)),
          Icon(Icons.local_offer_outlined,
              size: dpi.icon(48), color: MangoThemeFactory.mutedText(context)),
          SizedBox(height: dpi.space(12)),
          Center(
            child: Text(
              'No hay ofertas todavía.\nToca "Nueva oferta" para crear una.',
              textAlign: TextAlign.center,
              style: TextStyle(color: MangoThemeFactory.mutedText(context), fontSize: dpi.font(13)),
            ),
          ),
        ],
      );
    }

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.fromLTRB(dpi.space(16), dpi.space(14), dpi.space(16), dpi.space(90)),
      children: [
        for (final p in vm.promotions)
          _OfferCard(
            promo: p,
            saving: vm.savingIds.contains(p.id),
            onToggle: (v) => ref.read(offersAdminViewModelProvider.notifier).toggleActive(p.id, v),
            onEdit: () => _openForm(existing: p),
            onDelete: () => _confirmDelete(p),
          ),
      ],
    );
  }
}

class _OfferCard extends StatelessWidget {
  const _OfferCard({
    required this.promo,
    required this.saving,
    required this.onToggle,
    required this.onEdit,
    required this.onDelete,
  });

  final Promotion promo;
  final bool saving;
  final ValueChanged<bool> onToggle;
  final VoidCallback? onEdit;
  final VoidCallback onDelete;

  String get _discountLabel {
    if (!promo.isSimple) return promo.specialTypeLabel;
    if (promo.isPercentage) {
      final v = promo.discountValue;
      return '${v.toStringAsFixed(v.truncateToDouble() == v ? 0 : 2)}%';
    }
    return MangoFormatters.currency(promo.discountValue);
  }

  String get _appliesLabel {
    switch (promo.appliesTo.raw) {
      case 'product':
        return 'Productos (${promo.targetIds.length})';
      case 'category':
        return 'Categorías (${promo.targetIds.length})';
      default:
        return 'Todo el menú';
    }
  }

  String get _vigencia {
    final s = promo.startDate, e = promo.endDate;
    if (s == null && e == null) return 'Sin fecha límite';
    final sStr = s != null ? MangoFormatters.date(s) : '—';
    final eStr = e != null ? MangoFormatters.date(e) : '—';
    return '$sStr → $eStr';
  }

  @override
  Widget build(BuildContext context) {
    final dpi = DpiScale.of(context);
    final dimmed = !promo.isActive;
    return Opacity(
      opacity: dimmed ? 0.6 : 1,
      child: Container(
        margin: EdgeInsets.only(bottom: dpi.space(12)),
        padding: EdgeInsets.all(dpi.space(14)),
        decoration: BoxDecoration(
          color: MangoThemeFactory.cardColor(context),
          borderRadius: BorderRadius.circular(dpi.radius(16)),
          border: Border.all(color: MangoThemeFactory.borderColor(context)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: EdgeInsets.symmetric(horizontal: dpi.space(10), vertical: dpi.space(6)),
                  decoration: BoxDecoration(
                    color: MangoThemeFactory.mango.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(dpi.radius(10)),
                  ),
                  child: Text(
                    _discountLabel,
                    style: TextStyle(
                      fontSize: dpi.font(14),
                      fontWeight: FontWeight.w800,
                      color: MangoThemeFactory.mangoDeep,
                    ),
                  ),
                ),
                SizedBox(width: dpi.space(12)),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        promo.name,
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      if (!promo.isSimple)
                        Padding(
                          padding: EdgeInsets.only(top: dpi.space(2)),
                          child: Text(
                            'Tipo especial · solo se edita el horario',
                            style: TextStyle(
                              fontSize: dpi.font(11),
                              color: MangoThemeFactory.warning,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                if (saving)
                  SizedBox(
                    width: dpi.icon(20),
                    height: dpi.icon(20),
                    child: const CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  Switch(
                    value: promo.isActive,
                    activeThumbColor: MangoThemeFactory.success,
                    onChanged: onToggle,
                  ),
              ],
            ),
            SizedBox(height: dpi.space(8)),
            _meta(context, dpi, Icons.sell_outlined, _appliesLabel),
            _meta(context, dpi, Icons.event_outlined, _vigencia),
            _meta(context, dpi, Icons.today_outlined, '${promo.daysSummary} · ${promo.timeSummary}'),
            SizedBox(height: dpi.space(6)),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (onEdit != null)
                  TextButton.icon(
                    onPressed: onEdit,
                    icon: Icon(Icons.edit_outlined, size: dpi.icon(18)),
                    label: const Text('Editar'),
                  ),
                TextButton.icon(
                  onPressed: onDelete,
                  icon: Icon(Icons.delete_outline_rounded, size: dpi.icon(18), color: MangoThemeFactory.danger),
                  label: Text('Eliminar', style: TextStyle(color: MangoThemeFactory.danger)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _meta(BuildContext context, DpiScale dpi, IconData icon, String text) {
    return Padding(
      padding: EdgeInsets.only(top: dpi.space(4)),
      child: Row(
        children: [
          Icon(icon, size: dpi.icon(15), color: MangoThemeFactory.mutedText(context)),
          SizedBox(width: dpi.space(8)),
          Expanded(
            child: Text(
              text,
              style: TextStyle(fontSize: dpi.font(12), color: MangoThemeFactory.mutedText(context)),
            ),
          ),
        ],
      ),
    );
  }
}
