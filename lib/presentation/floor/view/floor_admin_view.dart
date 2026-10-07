import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/responsive/dpi_scale.dart';
import '../../../domain/floor/floor_models.dart';
import '../../auth/viewmodel/auth_gate_view_model.dart';
import '../../theme/theme_data_factory.dart';
import '../../widgets/soft_admin_parts.dart';
import '../viewmodel/floor_admin_view_model.dart';
import '../widgets/floor_dialogs.dart';
import 'zone_tables_view.dart';

/// Salón: las zonas del POS (Salón principal, Terraza…) en su orden. Cada
/// zona abre sus mesas. Las zonas desactivadas (con historial) se pueden
/// reactivar.
class FloorAdminView extends ConsumerStatefulWidget {
  const FloorAdminView({super.key});

  @override
  ConsumerState<FloorAdminView> createState() => _FloorAdminViewState();
}

class _FloorAdminViewState extends ConsumerState<FloorAdminView> {
  String? get _businessId =>
      ref.read(authGateViewModelProvider).profile?.businessId;

  FloorAdminViewModel get _vm => ref.read(floorAdminViewModelProvider.notifier);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final id = _businessId;
      if (id != null) _vm.load(id);
    });
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _createZone() async {
    final id = _businessId;
    if (id == null) return;
    final name = await showZoneNameDialog(context);
    if (name == null) return;
    final error = await _vm.createZone(id, name);
    _snack(error ?? 'Zona creada. Ábrela para agregarle mesas.');
  }

  Future<void> _reactivate(FloorZone zone) async {
    final id = _businessId;
    if (id == null) return;
    final error = await _vm.reactivateZone(id, zone);
    _snack(error ?? '${zone.name} está activa otra vez, con sus mesas.');
  }

  void _open(FloorZone zone) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => ZoneTablesView(zoneId: zone.id)));
  }

  @override
  Widget build(BuildContext context) {
    final vm = ref.watch(floorAdminViewModelProvider);
    final id = _businessId;

    ref.listen<FloorAdminState>(floorAdminViewModelProvider, (prev, next) {
      if (next.error != null && next.error != prev?.error) _snack(next.error!);
    });

    return Scaffold(
      appBar: AppBar(title: const Text('Salón')),
      floatingActionButton: (id == null || vm.zones.isEmpty)
          ? null
          : FloatingActionButton.extended(
              onPressed: vm.saving ? null : _createZone,
              backgroundColor: MangoThemeFactory.mango,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Nueva zona'),
            ),
      body: id == null
          ? const Center(child: Text('No hay un negocio activo.'))
          : RefreshIndicator(
              onRefresh: () => _vm.refresh(id),
              child: _body(context, vm, id),
            ),
    );
  }

  Widget _body(BuildContext context, FloorAdminState vm, String businessId) {
    final dpi = DpiScale.of(context);
    final padding = EdgeInsets.fromLTRB(
      dpi.space(16),
      dpi.space(8),
      dpi.space(16),
      dpi.space(96),
    );
    if (vm.isLoading && vm.zones.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (vm.zones.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: padding,
        children: [
          SizedBox(height: dpi.space(40)),
          SoftEmptyState(
            icon: Icons.table_restaurant_outlined,
            title: 'Aún no hay zonas',
            message:
                'Crea una zona (Salón, Terraza, Barra…) y luego agrégale sus mesas.',
            action: FilledButton.icon(
              onPressed: vm.saving ? null : _createZone,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Crear zona'),
            ),
          ),
        ],
      );
    }

    final active = vm.activeZones;
    final inactive = vm.inactiveZones;
    return ReorderableListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: padding,
      buildDefaultDragHandles: false,
      header: SoftSectionHeader(
        label: 'ZONAS',
        count: active.length,
        hint:
            'Toca una zona para ver sus mesas. Arrastra ⠿ para el orden del POS.',
      ),
      footer: inactive.isEmpty
          ? null
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(height: dpi.space(8)),
                SoftSectionHeader(
                  label: 'DESACTIVADAS',
                  count: inactive.length,
                  hint: 'Tienen historial de ventas, por eso no se borraron.',
                ),
                for (final z in inactive)
                  SoftRowCard(
                    muted: true,
                    leading: const SoftInitialAvatar(
                      text: '',
                      icon: Icons.table_restaurant_rounded,
                    ),
                    title: z.name,
                    subtitle: _tablesSummary(vm, z),
                    trailing: TextButton(
                      onPressed: vm.saving ? null : () => _reactivate(z),
                      child: const Text('Reactivar'),
                    ),
                  ),
              ],
            ),
      itemCount: active.length,
      onReorderItem: (oldIndex, newIndex) =>
          _vm.reorderZones(businessId, oldIndex, newIndex),
      itemBuilder: (context, index) {
        final z = active[index];
        return KeyedSubtree(
          key: ValueKey(z.id),
          child: SoftRowCard(
            onTap: () => _open(z),
            leading: const SoftInitialAvatar(
              text: '',
              icon: Icons.table_restaurant_rounded,
            ),
            title: z.name,
            subtitle: _tablesSummary(vm, z),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.chevron_right_rounded,
                  color: MangoThemeFactory.mutedText(context),
                ),
                ReorderableDragStartListener(
                  index: index,
                  child: Padding(
                    padding: EdgeInsets.all(dpi.space(4)),
                    child: Icon(
                      Icons.drag_indicator_rounded,
                      size: dpi.icon(20),
                      color: MangoThemeFactory.mutedText(context),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  String _tablesSummary(FloorAdminState vm, FloorZone zone) {
    final tables = vm.tablesOf(zone.id, active: true);
    if (tables.isEmpty) return 'Sin mesas';
    final busy = tables.where((t) => !t.isAvailable).length;
    final count = tables.length == 1 ? '1 mesa' : '${tables.length} mesas';
    return busy == 0 ? count : '$count · $busy ocupada${busy == 1 ? '' : 's'}';
  }
}
