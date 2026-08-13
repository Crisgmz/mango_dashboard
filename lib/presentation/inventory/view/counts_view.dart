import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/di/providers.dart';
import '../../../core/formatters/mango_formatters.dart';
import '../../../core/responsive/dpi_scale.dart';
import '../../../domain/inventory/inventory_models.dart';
import '../../../domain/inventory/physical_count_models.dart';
import '../../auth/viewmodel/auth_gate_view_model.dart';
import '../../theme/theme_data_factory.dart';
import 'count_detail_view.dart';

/// Sección Conteos del hub de Inventario (PRD 6.1 F5, estilo Square):
/// lista de sesiones de conteo físico con su estado, y creación de un conteo
/// nuevo (bodega + modo ciego). Content-only: vive dentro del hub.
class CountsView extends ConsumerStatefulWidget {
  const CountsView({super.key});

  @override
  ConsumerState<CountsView> createState() => _CountsViewState();
}

class _CountsViewState extends ConsumerState<CountsView> {
  List<CountSession> _sessions = const [];
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
      final sessions =
          await ref.read(physicalCountServiceProvider).loadSessions(businessId);
      if (mounted) {
        setState(() {
          _sessions = sessions;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _newCount() async {
    final businessId = _businessId;
    if (businessId == null) return;
    List<WarehouseInfo> warehouses;
    try {
      warehouses = await ref
          .read(purchasingDataServiceProvider)
          .loadWarehouses(businessId);
    } catch (_) {
      warehouses = const [];
    }
    if (!mounted) return;
    if (warehouses.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('No hay bodegas configuradas en el negocio.')));
      return;
    }

    final result = await showDialog<({String warehouseId, bool blind})>(
      context: context,
      builder: (_) => _NewCountDialog(warehouses: warehouses),
    );
    if (result == null || !mounted) return;

    try {
      final service = ref.read(physicalCountServiceProvider);
      final sessionId = await service.createSession(
        businessId: businessId,
        warehouseId: result.warehouseId,
        isBlind: result.blind,
      );
      // Congelar de una vez: el conteo queda listo para contar.
      await service.freeze(sessionId);
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
            builder: (_) => CountDetailView(sessionId: sessionId)),
      );
      _load();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('No se pudo crear el conteo. Intenta de nuevo.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final dpi = DpiScale.of(context);
    return Scaffold(
      appBar:
          AppBar(title: const Text('Conteos de stock'), centerTitle: false),
      body: RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(
            parent: BouncingScrollPhysics()),
        padding: EdgeInsets.fromLTRB(
            dpi.space(16), dpi.space(4), dpi.space(16), dpi.space(28)),
        children: [
          FilledButton.icon(
            onPressed: _newCount,
            style: FilledButton.styleFrom(
              backgroundColor: MangoThemeFactory.mango,
              padding: EdgeInsets.symmetric(vertical: dpi.space(12)),
            ),
            icon: const Icon(Icons.fact_check_outlined, size: 18),
            label: const Text('Nuevo conteo'),
          ),
          SizedBox(height: dpi.space(14)),
          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 60),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_sessions.isEmpty)
            Container(
              padding: EdgeInsets.all(dpi.space(28)),
              decoration: BoxDecoration(
                color: MangoThemeFactory.cardColor(context),
                borderRadius: BorderRadius.circular(dpi.radius(20)),
                border:
                    Border.all(color: MangoThemeFactory.borderColor(context)),
              ),
              child: Column(
                children: [
                  Icon(Icons.fact_check_outlined,
                      size: dpi.icon(42),
                      color: MangoThemeFactory.mutedText(context)
                          .withValues(alpha: 0.6)),
                  SizedBox(height: dpi.space(10)),
                  Text(
                    'Aún no hay conteos físicos.\nCrea el primero para auditar tu stock.',
                    textAlign: TextAlign.center,
                    style:
                        TextStyle(color: MangoThemeFactory.mutedText(context)),
                  ),
                ],
              ),
            )
          else
            ..._sessions.map((s) => _SessionCard(
                  session: s,
                  onTap: () async {
                    await Navigator.of(context).push(
                      MaterialPageRoute(
                          builder: (_) => CountDetailView(sessionId: s.id)),
                    );
                    _load();
                  },
                )),
        ],
      ),
      ),
    );
  }
}

Color _countStatusColor(String status) {
  switch (status) {
    case 'draft':
      return MangoThemeFactory.info;
    case 'in_progress':
      return MangoThemeFactory.warning;
    case 'completed':
      return MangoThemeFactory.success;
    case 'cancelled':
      return MangoThemeFactory.danger;
    default:
      return MangoThemeFactory.info;
  }
}

class _SessionCard extends StatelessWidget {
  const _SessionCard({required this.session, required this.onTap});

  final CountSession session;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final dpi = DpiScale.of(context);
    final color = _countStatusColor(session.status);
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
            padding: EdgeInsets.all(dpi.space(14)),
            child: Row(
              children: [
                Container(
                  width: dpi.scale(40),
                  height: dpi.scale(40),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(dpi.radius(12)),
                  ),
                  child: Icon(
                      session.isBlind
                          ? Icons.visibility_off_rounded
                          : Icons.fact_check_rounded,
                      color: color,
                      size: dpi.icon(20)),
                ),
                SizedBox(width: dpi.space(12)),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              session.warehouseName ?? 'Bodega',
                              style: TextStyle(
                                fontSize: dpi.font(14),
                                fontWeight: FontWeight.w700,
                                color: MangoThemeFactory.textColor(context),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (session.isBlind) ...[
                            SizedBox(width: dpi.space(6)),
                            Container(
                              padding: EdgeInsets.symmetric(
                                  horizontal: dpi.space(6),
                                  vertical: dpi.space(2)),
                              decoration: BoxDecoration(
                                color: MangoThemeFactory.info
                                    .withValues(alpha: 0.12),
                                borderRadius:
                                    BorderRadius.circular(dpi.radius(4)),
                              ),
                              child: Text(
                                'CIEGO',
                                style: TextStyle(
                                  fontSize: dpi.font(8.5),
                                  fontWeight: FontWeight.w800,
                                  color: MangoThemeFactory.info,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      SizedBox(height: dpi.space(2)),
                      Text(
                        [
                          session.code,
                          if (session.startedAt != null)
                            MangoFormatters.date(session.startedAt!),
                        ].join(' · '),
                        style: TextStyle(
                          fontSize: dpi.font(11),
                          color: MangoThemeFactory.mutedText(context),
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: EdgeInsets.symmetric(
                      horizontal: dpi.space(8), vertical: dpi.space(3)),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(dpi.radius(6)),
                  ),
                  child: Text(
                    session.statusLabel.toUpperCase(),
                    style: TextStyle(
                      fontSize: dpi.font(9),
                      fontWeight: FontWeight.w800,
                      color: color,
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

class _NewCountDialog extends StatefulWidget {
  const _NewCountDialog({required this.warehouses});

  final List<WarehouseInfo> warehouses;

  @override
  State<_NewCountDialog> createState() => _NewCountDialogState();
}

class _NewCountDialogState extends State<_NewCountDialog> {
  String? _warehouseId;
  bool _blind = false;

  @override
  void initState() {
    super.initState();
    _warehouseId = widget.warehouses.first.id;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Nuevo conteo físico'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DropdownButtonFormField<String>(
            initialValue: _warehouseId,
            decoration: const InputDecoration(labelText: 'Bodega'),
            items: [
              for (final w in widget.warehouses)
                DropdownMenuItem(
                    value: w.id,
                    child: Text(w.isMain ? '${w.name} (principal)' : w.name)),
            ],
            onChanged: (v) => setState(() => _warehouseId = v),
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Modo ciego'),
            subtitle: const Text(
              'El contador no ve la cantidad que espera el sistema.',
              style: TextStyle(fontSize: 12),
            ),
            value: _blind,
            onChanged: (v) => setState(() => _blind = v),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _warehouseId == null
              ? null
              : () => Navigator.of(context)
                  .pop((warehouseId: _warehouseId!, blind: _blind)),
          child: const Text('Iniciar conteo'),
        ),
      ],
    );
  }
}
