import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/role_mapper.dart';
import '../../../core/responsive/dpi_scale.dart';
import '../../../domain/purchasing/supplier.dart';
import '../../auth/viewmodel/auth_gate_view_model.dart';
import '../../theme/theme_data_factory.dart';
import '../viewmodel/suppliers_view_model.dart';
import 'supplier_form_view.dart';

/// Suplidores del negocio (módulo de compras · PRD 6.1 F1). La RLS del
/// backend limita la escritura a owner/admin; manager ve la lista en solo
/// lectura.
class SuppliersAdminView extends ConsumerStatefulWidget {
  const SuppliersAdminView({super.key});

  @override
  ConsumerState<SuppliersAdminView> createState() => _SuppliersAdminViewState();
}

class _SuppliersAdminViewState extends ConsumerState<SuppliersAdminView> {
  String _query = '';

  String? get _businessId =>
      ref.read(authGateViewModelProvider).profile?.businessId;

  bool get _canWrite => isOwnerOrAdminRole(
      ref.read(authGateViewModelProvider).profile?.normalizedRole);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final id = _businessId;
      if (id != null) ref.read(suppliersViewModelProvider.notifier).load(id);
    });
  }

  Future<void> _refresh() async {
    final id = _businessId;
    if (id != null) {
      await ref.read(suppliersViewModelProvider.notifier).refresh(id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dpi = DpiScale.of(context);
    final vm = ref.watch(suppliersViewModelProvider);
    final id = _businessId;

    ref.listen<SuppliersState>(suppliersViewModelProvider, (prev, next) {
      if (next.error != null && next.error != prev?.error) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(next.error!)));
      }
    });

    final filtered = _query.isEmpty
        ? vm.suppliers
        : vm.suppliers
            .where((s) =>
                s.name.toLowerCase().contains(_query.toLowerCase()) ||
                (s.rnc?.contains(_query) ?? false))
            .toList(growable: false);

    return Scaffold(
      appBar: AppBar(title: const Text('Suplidores')),
      floatingActionButton: (id == null || !_canWrite)
          ? null
          : FloatingActionButton.extended(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SupplierFormView()),
              ),
              backgroundColor: MangoThemeFactory.mango,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Nuevo suplidor'),
            ),
      body: id == null
          ? const Center(child: Text('No hay un negocio activo.'))
          : Column(
              children: [
                Padding(
                  padding: EdgeInsets.fromLTRB(
                      dpi.space(16), dpi.space(12), dpi.space(16), dpi.space(4)),
                  child: TextField(
                    onChanged: (v) => setState(() => _query = v),
                    decoration: const InputDecoration(
                      hintText: 'Buscar por nombre o RNC…',
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

  Widget _body(BuildContext context, DpiScale dpi, SuppliersState vm,
      List<Supplier> items) {
    if (vm.isLoading && vm.suppliers.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (items.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          SizedBox(height: dpi.space(120)),
          Center(
            child: Text(
              vm.suppliers.isEmpty
                  ? 'Aún no hay suplidores. Crea el primero con el botón +.'
                  : 'Sin resultados.',
              style: TextStyle(color: MangoThemeFactory.mutedText(context)),
            ),
          ),
        ],
      );
    }

    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.fromLTRB(
          dpi.space(16), dpi.space(8), dpi.space(16), dpi.space(96)),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final s = items[index];
        return _SupplierRow(
          supplier: s,
          canWrite: _canWrite,
          saving: vm.savingIds.contains(s.id),
          onChanged: (v) {
            final id = _businessId;
            if (id != null) {
              ref.read(suppliersViewModelProvider.notifier).toggle(id, s.id, v);
            }
          },
          onTap: !_canWrite
              ? null
              : () => Navigator.of(context).push(
                    MaterialPageRoute(
                        builder: (_) => SupplierFormView(existing: s)),
                  ),
        );
      },
    );
  }
}

class _SupplierRow extends StatelessWidget {
  const _SupplierRow({
    required this.supplier,
    required this.canWrite,
    required this.saving,
    required this.onChanged,
    required this.onTap,
  });

  final Supplier supplier;
  final bool canWrite;
  final bool saving;
  final ValueChanged<bool> onChanged;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final dpi = DpiScale.of(context);
    final s = supplier;
    final subtitleParts = <String>[
      if (s.rnc != null && s.rnc!.isNotEmpty)
        '${(s.taxIdType ?? 'rnc').toUpperCase()} ${s.rnc}',
      if (s.phone != null && s.phone!.isNotEmpty) s.phone!,
      s.paymentTermsDays > 0 ? '${s.paymentTermsDays} días' : 'Contado',
    ];
    return Container(
      margin: EdgeInsets.only(bottom: dpi.space(8)),
      decoration: BoxDecoration(
        color: MangoThemeFactory.cardColor(context),
        borderRadius: BorderRadius.circular(dpi.radius(14)),
        border: Border.all(color: MangoThemeFactory.borderColor(context)),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(dpi.radius(14)),
          child: Padding(
            padding: EdgeInsets.symmetric(
                horizontal: dpi.space(14), vertical: dpi.space(10)),
            child: Row(
              children: [
                Container(
                  width: dpi.scale(38),
                  height: dpi.scale(38),
                  decoration: BoxDecoration(
                    color: MangoThemeFactory.mango.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(dpi.radius(10)),
                  ),
                  child: Icon(Icons.local_shipping_rounded,
                      color: MangoThemeFactory.mango, size: dpi.icon(20)),
                ),
                SizedBox(width: dpi.space(12)),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        s.name,
                        style: TextStyle(
                          fontSize: dpi.font(14),
                          fontWeight: FontWeight.w600,
                          color: MangoThemeFactory.textColor(context),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      SizedBox(height: dpi.space(2)),
                      Text(
                        subtitleParts.join(' · '),
                        style: TextStyle(
                          fontSize: dpi.font(11.5),
                          color: s.isActive
                              ? MangoThemeFactory.mutedText(context)
                              : MangoThemeFactory.danger,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                SizedBox(width: dpi.space(8)),
                if (canWrite) ...[
                  Icon(Icons.edit_rounded,
                      size: dpi.icon(16),
                      color: MangoThemeFactory.mutedText(context)),
                  SizedBox(width: dpi.space(8)),
                  if (saving)
                    SizedBox(
                      width: dpi.icon(20),
                      height: dpi.icon(20),
                      child: const CircularProgressIndicator(strokeWidth: 2),
                    )
                  else
                    Switch(
                      value: s.isActive,
                      activeThumbColor: MangoThemeFactory.success,
                      onChanged: onChanged,
                    ),
                ] else if (!s.isActive)
                  Container(
                    padding: EdgeInsets.symmetric(
                        horizontal: dpi.space(8), vertical: dpi.space(3)),
                    decoration: BoxDecoration(
                      color: MangoThemeFactory.danger.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(dpi.radius(6)),
                    ),
                    child: Text(
                      'INACTIVO',
                      style: TextStyle(
                        fontSize: dpi.font(9),
                        fontWeight: FontWeight.w800,
                        color: MangoThemeFactory.danger,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
