import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/responsive/dpi_scale.dart';
import '../../../domain/floor/floor_models.dart';
import '../../auth/viewmodel/auth_gate_view_model.dart';
import '../../theme/theme_data_factory.dart';
import '../../widgets/soft_admin_parts.dart';
import '../viewmodel/floor_admin_view_model.dart';
import '../widgets/floor_dialogs.dart';

/// Mesas de una zona: crear (una o varias), editar, mover de zona, eliminar
/// y reactivar. Desde el menú: renombrar o eliminar la zona.
class ZoneTablesView extends ConsumerStatefulWidget {
  const ZoneTablesView({super.key, required this.zoneId});

  final String zoneId;

  @override
  ConsumerState<ZoneTablesView> createState() => _ZoneTablesViewState();
}

enum _ZoneAction { rename, bulk, delete }

class _ZoneTablesViewState extends ConsumerState<ZoneTablesView> {
  String? get _businessId =>
      ref.read(authGateViewModelProvider).profile?.businessId;

  FloorAdminViewModel get _vm => ref.read(floorAdminViewModelProvider.notifier);

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _createTable() async {
    final id = _businessId;
    if (id == null) return;
    final result = await showTableDialog(
      context,
      zoneId: widget.zoneId,
      zones: ref.read(floorAdminViewModelProvider).activeZones,
    );
    if (result == null || result.delete) return;
    final error = await _vm.createTable(
      id,
      zoneId: widget.zoneId,
      code: result.code,
      label: result.label,
      capacity: result.capacity,
    );
    _snack(error ?? 'Mesa ${result.code} creada.');
  }

  Future<void> _editTable(FloorTable table) async {
    final id = _businessId;
    if (id == null) return;
    final result = await showTableDialog(
      context,
      zoneId: widget.zoneId,
      zones: ref.read(floorAdminViewModelProvider).activeZones,
      existing: table,
    );
    if (result == null) return;
    if (result.delete) {
      await _deleteTable(table);
      return;
    }
    final error = await _vm.updateTable(
      id,
      table,
      code: result.code,
      label: result.label,
      capacity: result.capacity,
      zoneId: result.zoneId,
    );
    if (error != null) {
      _snack(error);
    } else if (result.zoneId != widget.zoneId) {
      final target = ref
          .read(floorAdminViewModelProvider)
          .zoneById(result.zoneId);
      _snack('Mesa movida a ${target?.name ?? 'otra zona'}.');
    } else {
      _snack('Mesa guardada.');
    }
  }

  Future<void> _deleteTable(FloorTable table) async {
    final id = _businessId;
    if (id == null) return;
    final ok = await confirmFloorDelete(
      context,
      title: 'Eliminar ${table.displayName}',
      detail:
          'Si la mesa tiene historial de ventas, se desactiva en vez de '
          'borrarse: deja de verse en el POS y el historial no se pierde.',
    );
    if (!ok) return;
    final result = await _vm.deleteTable(id, table);
    _snack(
      result.error ??
          (result.outcome == FloorDeleteOutcome.deactivated
              ? '${table.displayName} tenía historial: quedó desactivada.'
              : '${table.displayName} eliminada.'),
    );
  }

  Future<void> _reactivateTable(FloorTable table) async {
    final id = _businessId;
    if (id == null) return;
    final error = await _vm.reactivateTable(id, table);
    _snack(error ?? '${table.displayName} está activa otra vez.');
  }

  Future<void> _bulkCreate() async {
    final id = _businessId;
    if (id == null) return;
    final input = await showBulkTablesDialog(context);
    if (input == null) return;
    final result = await _vm.createTablesBulk(
      id,
      zoneId: widget.zoneId,
      prefix: input.prefix,
      from: input.from,
      to: input.to,
      capacity: input.capacity,
    );
    if (result.error != null) {
      _snack(result.error!);
      return;
    }
    final created = result.created == 1
        ? '1 mesa creada'
        : '${result.created} mesas creadas';
    _snack(
      result.skipped == 0
          ? '$created.'
          : '$created · ${result.skipped} ya existían.',
    );
  }

  Future<void> _onZoneAction(_ZoneAction action, FloorZone zone) async {
    final id = _businessId;
    if (id == null) return;
    switch (action) {
      case _ZoneAction.rename:
        final name = await showZoneNameDialog(context, existing: zone);
        if (name == null) return;
        final error = await _vm.renameZone(id, zone, name);
        _snack(error ?? 'Zona guardada.');
      case _ZoneAction.bulk:
        await _bulkCreate();
      case _ZoneAction.delete:
        final tables = ref
            .read(floorAdminViewModelProvider)
            .tablesOf(zone.id, active: true)
            .length;
        final ok = await confirmFloorDelete(
          context,
          title: 'Eliminar ${zone.name}',
          detail:
              '${tables == 0 ? 'La zona no tiene mesas.' : 'Se eliminan también sus $tables mesa${tables == 1 ? '' : 's'}.'} '
              'Si alguna tiene historial de ventas, la zona y sus mesas se '
              'desactivan en vez de borrarse (el historial no se pierde).',
        );
        if (!ok) return;
        final result = await _vm.deleteZone(id, zone);
        if (result.error != null) {
          _snack(result.error!);
          return;
        }
        _snack(
          result.outcome == FloorDeleteOutcome.deactivated
              ? '${zone.name} tenía historial: quedó desactivada con sus mesas.'
              : '${zone.name} eliminada.',
        );
        if (mounted) Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final dpi = DpiScale.of(context);
    final vm = ref.watch(floorAdminViewModelProvider);
    final zone = vm.zoneById(widget.zoneId);
    final id = _businessId;

    if (zone == null || id == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Zona')),
        body: Center(
          child: vm.isLoading
              ? const CircularProgressIndicator()
              : const Text('Esta zona ya no existe.'),
        ),
      );
    }

    final active = vm.tablesOf(zone.id, active: true);
    final inactive = vm.tablesOf(zone.id, active: false);
    final padding = EdgeInsets.fromLTRB(
      dpi.space(16),
      dpi.space(8),
      dpi.space(16),
      dpi.space(96),
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(zone.name),
        actions: [
          PopupMenuButton<_ZoneAction>(
            enabled: !vm.saving,
            onSelected: (a) => _onZoneAction(a, zone),
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: _ZoneAction.rename,
                child: Text('Renombrar zona'),
              ),
              const PopupMenuItem(
                value: _ZoneAction.bulk,
                child: Text('Crear varias mesas'),
              ),
              PopupMenuItem(
                value: _ZoneAction.delete,
                child: Text(
                  'Eliminar zona',
                  style: TextStyle(color: MangoThemeFactory.danger),
                ),
              ),
            ],
          ),
        ],
      ),
      floatingActionButton: active.isEmpty && inactive.isEmpty
          ? null
          : FloatingActionButton.extended(
              onPressed: vm.saving ? null : _createTable,
              backgroundColor: MangoThemeFactory.mango,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Nueva mesa'),
            ),
      body: RefreshIndicator(
        onRefresh: () => _vm.refresh(id),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: padding,
          children: [
            if (active.isEmpty && inactive.isEmpty) ...[
              SizedBox(height: dpi.space(40)),
              SoftEmptyState(
                icon: Icons.chair_alt_outlined,
                title: 'Esta zona no tiene mesas',
                message:
                    'Agrega una mesa, o crea varias de una vez (T01, T02 … T20).',
                action: Wrap(
                  alignment: WrapAlignment.center,
                  spacing: dpi.space(8),
                  runSpacing: dpi.space(8),
                  children: [
                    FilledButton.icon(
                      onPressed: vm.saving ? null : _createTable,
                      icon: const Icon(Icons.add_rounded),
                      label: const Text('Nueva mesa'),
                    ),
                    OutlinedButton.icon(
                      onPressed: vm.saving ? null : _bulkCreate,
                      icon: const Icon(Icons.library_add_rounded),
                      label: const Text('Crear varias'),
                    ),
                  ],
                ),
              ),
            ] else ...[
              SoftSectionHeader(
                label: 'MESAS',
                count: active.length,
                hint:
                    'Toca una mesa para editarla, moverla de zona o eliminarla.',
                trailing: TextButton.icon(
                  onPressed: vm.saving ? null : _bulkCreate,
                  icon: Icon(Icons.library_add_rounded, size: dpi.icon(16)),
                  label: const Text('Varias'),
                ),
              ),
              for (final t in active)
                SoftRowCard(
                  onTap: vm.saving ? null : () => _editTable(t),
                  leading: SoftInitialAvatar(text: t.code),
                  title: t.displayName,
                  subtitle: [
                    if (t.displayName != t.code) 'Código ${t.code}',
                    t.capacity == 1 ? '1 persona' : '${t.capacity} personas',
                  ].join(' · '),
                  trailing: t.stateLabel == null
                      ? Icon(
                          Icons.edit_rounded,
                          size: dpi.icon(16),
                          color: MangoThemeFactory.mutedText(context),
                        )
                      : SoftStatusPill(
                          text: t.stateLabel!,
                          color: MangoThemeFactory.warning,
                        ),
                ),
              if (inactive.isNotEmpty) ...[
                SizedBox(height: dpi.space(8)),
                SoftSectionHeader(
                  label: 'DESACTIVADAS',
                  count: inactive.length,
                  hint: 'Tienen historial de ventas, por eso no se borraron.',
                ),
                for (final t in inactive)
                  SoftRowCard(
                    muted: true,
                    leading: SoftInitialAvatar(text: t.code),
                    title: t.displayName,
                    subtitle: t.displayName != t.code
                        ? 'Código ${t.code}'
                        : null,
                    trailing: TextButton(
                      onPressed: vm.saving ? null : () => _reactivateTable(t),
                      child: const Text('Reactivar'),
                    ),
                  ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}
