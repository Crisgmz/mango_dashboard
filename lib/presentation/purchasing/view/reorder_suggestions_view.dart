import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/di/providers.dart';
import '../../../core/formatters/mango_formatters.dart';
import '../../../core/responsive/dpi_scale.dart';
import '../../../domain/purchasing/purchase_order.dart';
import '../../../domain/purchasing/reorder_suggestion.dart';
import '../../auth/viewmodel/auth_gate_view_model.dart';
import '../../theme/theme_data_factory.dart';
import 'purchase_order_form_view.dart';

/// "Qué comprar hoy" (PRD 6.2): sugerencias de reorden agrupadas por
/// suplidor sugerido (el de la última compra). Marca/desmarca artículos y
/// convierte cada grupo en una OC borrador en un toque, con líneas, costos
/// y suplidor precargados.
class ReorderSuggestionsView extends ConsumerStatefulWidget {
  const ReorderSuggestionsView({super.key});

  @override
  ConsumerState<ReorderSuggestionsView> createState() =>
      _ReorderSuggestionsViewState();
}

class _ReorderSuggestionsViewState
    extends ConsumerState<ReorderSuggestionsView> {
  List<ReorderSuggestion> _suggestions = const [];
  final Set<String> _unchecked = {};
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
      final suggestions = await ref
          .read(purchasingDataServiceProvider)
          .loadReorderSuggestions(businessId);
      if (mounted) {
        setState(() {
          _suggestions = suggestions;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Grupos por suplidor sugerido; null = "Sin suplidor sugerido" al final.
  Map<String?, List<ReorderSuggestion>> get _groups {
    final map = <String?, List<ReorderSuggestion>>{};
    for (final s in _suggestions) {
      (map[s.supplierId] ??= []).add(s);
    }
    return map;
  }

  List<ReorderSuggestion> _selectedOf(List<ReorderSuggestion> group) =>
      group.where((s) => !_unchecked.contains(s.itemId)).toList();

  void _createOrder(List<ReorderSuggestion> group, String? supplierId) {
    final selected = _selectedOf(group);
    if (selected.isEmpty) return;
    Navigator.of(context)
        .push(
          MaterialPageRoute(
            builder: (_) => PurchaseOrderFormView(
              initialSupplierId: supplierId,
              initialLines: [
                for (final s in selected)
                  PurchaseOrderLineDraft(
                    inventoryItemId: s.itemId,
                    description: s.name,
                    quantity: s.suggestedQty,
                    unitCost: s.unitCost,
                    taxRate: 18,
                    unit: s.unit,
                  ),
              ],
            ),
          ),
        )
        .then((_) => _load());
  }

  @override
  Widget build(BuildContext context) {
    final dpi = DpiScale.of(context);
    final groups = _groups.entries.toList()
      ..sort((a, b) {
        // Con suplidor primero; "sin suplidor" al final.
        if (a.key == null) return 1;
        if (b.key == null) return -1;
        return b.value.length.compareTo(a.value.length);
      });

    return Scaffold(
      appBar:
          AppBar(title: const Text('Qué comprar hoy'), centerTitle: false),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: _suggestions.isEmpty
                  ? ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: EdgeInsets.all(dpi.space(24)),
                      children: [
                        SizedBox(height: dpi.space(60)),
                        Icon(Icons.check_circle_outline_rounded,
                            size: dpi.icon(48),
                            color: MangoThemeFactory.success),
                        SizedBox(height: dpi.space(12)),
                        Text(
                          'Nada que comprar hoy:\nningún artículo está bajo su punto de reorden.',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        SizedBox(height: dpi.space(8)),
                        Text(
                          'Configura puntos de reorden en la ficha de cada artículo para recibir sugerencias.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: dpi.font(11.5),
                            color: MangoThemeFactory.mutedText(context),
                          ),
                        ),
                      ],
                    )
                  : ListView(
                      physics: const AlwaysScrollableScrollPhysics(
                          parent: BouncingScrollPhysics()),
                      padding: EdgeInsets.fromLTRB(dpi.space(16),
                          dpi.space(12), dpi.space(16), dpi.space(28)),
                      children: [
                        for (final entry in groups) ...[
                          _groupCard(context, dpi, entry.key, entry.value),
                          SizedBox(height: dpi.space(12)),
                        ],
                      ],
                    ),
            ),
    );
  }

  Widget _groupCard(BuildContext context, DpiScale dpi, String? supplierId,
      List<ReorderSuggestion> group) {
    final selected = _selectedOf(group);
    final total =
        selected.fold<double>(0, (sum, s) => sum + s.estimatedTotal);
    final supplierName = group.first.supplierName;

    return Container(
      decoration: BoxDecoration(
        color: MangoThemeFactory.cardColor(context),
        borderRadius: BorderRadius.circular(dpi.radius(16)),
        border: Border.all(color: MangoThemeFactory.borderColor(context)),
      ),
      child: Column(
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(
                dpi.space(14), dpi.space(12), dpi.space(14), dpi.space(4)),
            child: Row(
              children: [
                Icon(
                  supplierId != null
                      ? Icons.local_shipping_rounded
                      : Icons.help_outline_rounded,
                  size: dpi.icon(16),
                  color: MangoThemeFactory.mango,
                ),
                SizedBox(width: dpi.space(6)),
                Expanded(
                  child: Text(
                    supplierId != null
                        ? (supplierName ?? 'Suplidor')
                        : 'Sin suplidor sugerido',
                    style: TextStyle(
                        fontSize: dpi.font(13.5),
                        fontWeight: FontWeight.w800),
                  ),
                ),
                Text(
                  '${selected.length} de ${group.length}',
                  style: TextStyle(
                    fontSize: dpi.font(11),
                    color: MangoThemeFactory.mutedText(context),
                  ),
                ),
              ],
            ),
          ),
          ...group.map((s) {
            final checked = !_unchecked.contains(s.itemId);
            return CheckboxListTile(
              value: checked,
              dense: true,
              controlAffinity: ListTileControlAffinity.leading,
              activeColor: MangoThemeFactory.mango,
              onChanged: (v) => setState(() {
                if (v == true) {
                  _unchecked.remove(s.itemId);
                } else {
                  _unchecked.add(s.itemId);
                }
              }),
              title: Text(
                s.name,
                style: TextStyle(
                    fontSize: dpi.font(13), fontWeight: FontWeight.w600),
              ),
              subtitle: Text(
                'Quedan ${MangoFormatters.number(s.currentStock)} de mín. ${MangoFormatters.number(s.minStock)} · '
                'sugerido ${MangoFormatters.number(s.suggestedQty)} ${s.unit}'
                '${s.unitCost > 0 ? ' × ${MangoFormatters.currency(s.unitCost)}' : ''}',
                style: TextStyle(
                  fontSize: dpi.font(10.5),
                  color: MangoThemeFactory.mutedText(context),
                ),
              ),
              secondary: Text(
                s.estimatedTotal > 0
                    ? MangoFormatters.currency(s.estimatedTotal)
                    : '—',
                style: TextStyle(
                    fontSize: dpi.font(12), fontWeight: FontWeight.w700),
              ),
            );
          }),
          Padding(
            padding: EdgeInsets.fromLTRB(
                dpi.space(14), dpi.space(2), dpi.space(14), dpi.space(12)),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Estimado: ${MangoFormatters.currency(total)}',
                    style: TextStyle(
                        fontSize: dpi.font(12.5),
                        fontWeight: FontWeight.w800),
                  ),
                ),
                FilledButton.icon(
                  onPressed: selected.isEmpty
                      ? null
                      : () => _createOrder(group, supplierId),
                  style: FilledButton.styleFrom(
                    backgroundColor: MangoThemeFactory.mango,
                    padding: EdgeInsets.symmetric(
                        horizontal: dpi.space(14),
                        vertical: dpi.space(10)),
                  ),
                  icon: const Icon(Icons.post_add_rounded, size: 16),
                  label: Text('Crear OC (${selected.length})'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
