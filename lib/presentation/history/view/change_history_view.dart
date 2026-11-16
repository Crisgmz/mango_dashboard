import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/formatters/mango_formatters.dart';
import '../../../core/responsive/dpi_scale.dart';
import '../../../domain/history/change_history_entry.dart';
import '../../auth/viewmodel/auth_gate_view_model.dart';
import '../../theme/theme_data_factory.dart';
import '../../widgets/soft_admin_parts.dart';
import '../change_history_text.dart';
import '../viewmodel/change_history_view_model.dart';

/// Historial: todo lo que se crea, cambia o borra en el negocio, quién lo
/// hizo y cuándo. Lo llena la base de datos sola (triggers); aquí solo se
/// lee. Solo dueño y administradores (la RLS no le devuelve nada a nadie más).
class ChangeHistoryView extends ConsumerStatefulWidget {
  const ChangeHistoryView({super.key});

  @override
  ConsumerState<ChangeHistoryView> createState() => _ChangeHistoryViewState();
}

class _ChangeHistoryViewState extends ConsumerState<ChangeHistoryView> {
  final _search = TextEditingController();
  Timer? _debounce;

  String? get _businessId =>
      ref.read(authGateViewModelProvider).profile?.businessId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final id = _businessId;
      if (id != null) {
        ref.read(changeHistoryViewModelProvider.notifier).load(id);
      }
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    setState(() {}); // muestra u oculta la X
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      ref.read(changeHistoryViewModelProvider.notifier).setSearch(value);
    });
  }

  void _clearSearch() {
    _debounce?.cancel();
    _search.clear();
    setState(() {});
    ref.read(changeHistoryViewModelProvider.notifier).setSearch('');
  }

  @override
  Widget build(BuildContext context) {
    final dpi = DpiScale.of(context);
    final vm = ref.watch(changeHistoryViewModelProvider);
    final notifier = ref.read(changeHistoryViewModelProvider.notifier);
    final muted = MangoThemeFactory.mutedText(context);
    final id = _businessId;

    ref.listen<ChangeHistoryState>(changeHistoryViewModelProvider, (
      prev,
      next,
    ) {
      if (next.error != null && next.error != prev?.error) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(next.error!)));
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('Historial'),
        centerTitle: false,
        actions: [
          IconButton(
            tooltip: 'Actualizar',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: id == null ? null : notifier.refresh,
          ),
        ],
      ),
      body: id == null
          ? const Center(child: Text('No hay un negocio activo.'))
          : RefreshIndicator(
              onRefresh: notifier.refresh,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(
                  parent: BouncingScrollPhysics(),
                ),
                padding: EdgeInsets.fromLTRB(
                  dpi.space(16),
                  dpi.space(12),
                  dpi.space(16),
                  dpi.space(32),
                ),
                children: [
                  Text(
                    'Todo lo que se crea, cambia o borra en el negocio, '
                    'quién lo hizo y cuándo.',
                    style: TextStyle(fontSize: dpi.font(12.5), color: muted),
                  ),
                  SizedBox(height: dpi.space(12)),
                  TextField(
                    controller: _search,
                    onChanged: _onSearchChanged,
                    textInputAction: TextInputAction.search,
                    decoration: InputDecoration(
                      hintText: 'Buscar producto, mesa o persona…',
                      prefixIcon: const Icon(Icons.search_rounded),
                      suffixIcon: _search.text.isEmpty
                          ? null
                          : IconButton(
                              tooltip: 'Borrar búsqueda',
                              icon: const Icon(Icons.close_rounded),
                              onPressed: _clearSearch,
                            ),
                    ),
                  ),
                  SizedBox(height: dpi.space(12)),
                  _ChipRow(
                    children: [
                      for (final area in historyAreas)
                        _FilterChip(
                          label: area.label,
                          selected: vm.area == area.key,
                          onTap: () => notifier.setArea(area.key),
                        ),
                    ],
                  ),
                  SizedBox(height: dpi.space(8)),
                  _ChipRow(
                    children: [
                      for (final (value, label) in historyActions)
                        _FilterChip(
                          label: label,
                          selected: vm.action == value,
                          onTap: () => notifier.setAction(value),
                        ),
                    ],
                  ),
                  SizedBox(height: dpi.space(12)),
                  ..._body(context, vm, notifier),
                  SizedBox(height: dpi.space(16)),
                  Text(
                    'Nadie puede borrar ni cambiar este historial, '
                    'ni siquiera el dueño.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: dpi.font(11), color: muted),
                  ),
                ],
              ),
            ),
    );
  }

  List<Widget> _body(
    BuildContext context,
    ChangeHistoryState vm,
    ChangeHistoryViewModel notifier,
  ) {
    final dpi = DpiScale.of(context);
    if (vm.notActivated) {
      return const [
        SoftEmptyState(
          icon: Icons.history_toggle_off_rounded,
          title: 'El historial no está activado',
          message:
              'Todavía no está encendido en el servidor. Escríbele a soporte '
              'de MangoPOS para activarlo.',
        ),
      ];
    }
    if (vm.isLoading && vm.entries.isEmpty) {
      return [
        Padding(
          padding: EdgeInsets.symmetric(vertical: dpi.space(40)),
          child: const Center(child: CircularProgressIndicator()),
        ),
      ];
    }
    if (vm.entries.isEmpty) {
      return [
        SoftEmptyState(
          icon: Icons.history_rounded,
          title: vm.hasFilters
              ? 'No hay cambios con ese filtro'
              : 'Todavía no hay cambios',
          message: vm.hasFilters
              ? 'Prueba con otra búsqueda o vuelve a «Todo».'
              : 'Desde ahora, todo lo que se cree, cambie o borre queda aquí.',
        ),
      ];
    }

    final now = DateTime.now();
    final out = <Widget>[];
    String? day;
    for (final entry in vm.entries) {
      final label = historyDayLabel(entry.changedAt, now: now);
      if (label != day) {
        day = label;
        out.add(SoftSectionHeader(label: label.toUpperCase()));
      }
      out.add(_HistoryTile(key: ValueKey(entry.id), entry: entry));
    }
    if (vm.hasMore || vm.isLoadingMore) {
      out.add(
        Padding(
          padding: EdgeInsets.only(top: dpi.space(8)),
          child: Center(
            child: OutlinedButton(
              onPressed: vm.isLoadingMore ? null : notifier.loadMore,
              child: vm.isLoadingMore
                  ? SizedBox(
                      width: dpi.scale(16),
                      height: dpi.scale(16),
                      child: const CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Ver más'),
            ),
          ),
        ),
      );
    }
    return out;
  }
}

class _ChipRow extends StatelessWidget {
  const _ChipRow({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: DpiScale.of(context).scale(34),
      child: ListView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        children: children,
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final dpi = DpiScale.of(context);
    return Padding(
      padding: EdgeInsets.only(right: dpi.space(6)),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => onTap(),
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

/// Una línea del historial. Las ediciones muestran antes → después de una
/// vez; lo creado, borrado o anulado guarda la foto detrás de «Ver detalles».
class _HistoryTile extends StatefulWidget {
  const _HistoryTile({super.key, required this.entry});

  final ChangeHistoryEntry entry;

  @override
  State<_HistoryTile> createState() => _HistoryTileState();
}

class _HistoryTileState extends State<_HistoryTile> {
  late bool _open = widget.entry.action == 'update';

  static Color _color(String action) => switch (action) {
    'create' => MangoThemeFactory.success,
    'update' => MangoThemeFactory.warning,
    _ => MangoThemeFactory.danger,
  };

  static IconData _icon(String action) => switch (action) {
    'create' => Icons.add_rounded,
    'update' => Icons.edit_rounded,
    'void' => Icons.block_rounded,
    _ => Icons.delete_outline_rounded,
  };

  @override
  Widget build(BuildContext context) {
    final dpi = DpiScale.of(context);
    final e = widget.entry;
    const reader = HistoryText(money: MangoFormatters.currency);
    final lines = reader.details(e);
    final muted = MangoThemeFactory.mutedText(context);
    final text = MangoThemeFactory.textColor(context);
    final radius = BorderRadius.circular(dpi.radius(14));
    final canToggle = lines.isNotEmpty && e.action != 'update';
    final area = historyAreaLabel(e.tableName);

    return Container(
      margin: EdgeInsets.only(bottom: dpi.space(8)),
      decoration: BoxDecoration(
        color: MangoThemeFactory.cardColor(context),
        borderRadius: radius,
        border: Border.all(color: MangoThemeFactory.borderColor(context)),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: radius,
          onTap: canToggle ? () => setState(() => _open = !_open) : null,
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: dpi.space(12),
              vertical: dpi.space(10),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SoftInitialAvatar(
                  text: '',
                  color: _color(e.action),
                  icon: _icon(e.action),
                ),
                SizedBox(width: dpi.space(12)),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        reader.sentence(e),
                        style: TextStyle(
                          fontSize: dpi.font(13.5),
                          fontWeight: FontWeight.w700,
                          color: text,
                        ),
                      ),
                      SizedBox(height: dpi.space(2)),
                      Text(
                        [
                          historyTime(e.changedAt),
                          if (area.isNotEmpty) area,
                        ].join(' · '),
                        style: TextStyle(fontSize: dpi.font(11), color: muted),
                      ),
                      AnimatedSize(
                        duration: const Duration(milliseconds: 180),
                        alignment: Alignment.topLeft,
                        child: !_open || lines.isEmpty
                            ? const SizedBox(width: double.infinity)
                            : Container(
                                width: double.infinity,
                                margin: EdgeInsets.only(top: dpi.space(8)),
                                padding: EdgeInsets.all(dpi.space(10)),
                                decoration: BoxDecoration(
                                  color: MangoThemeFactory.altSurface(context),
                                  borderRadius: BorderRadius.circular(
                                    dpi.radius(10),
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    for (final line in lines)
                                      Padding(
                                        padding: EdgeInsets.symmetric(
                                          vertical: dpi.space(2),
                                        ),
                                        child: _LineText(line: line),
                                      ),
                                  ],
                                ),
                              ),
                      ),
                      if (canToggle)
                        Padding(
                          padding: EdgeInsets.only(top: dpi.space(6)),
                          child: Text(
                            _open
                                ? 'Ocultar detalles'
                                : e.action == 'delete'
                                ? 'Ver lo que se borró'
                                : 'Ver detalles',
                            style: TextStyle(
                              fontSize: dpi.font(11.5),
                              fontWeight: FontWeight.w700,
                              color: MangoThemeFactory.mango,
                            ),
                          ),
                        ),
                    ],
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

class _LineText extends StatelessWidget {
  const _LineText({required this.line});

  final HistoryLine line;

  @override
  Widget build(BuildContext context) {
    final dpi = DpiScale.of(context);
    final text = MangoThemeFactory.textColor(context);
    final muted = MangoThemeFactory.mutedText(context);
    final base = TextStyle(fontSize: dpi.font(12), color: text);
    final strong = base.copyWith(fontWeight: FontWeight.w700);
    return Text.rich(
      TextSpan(
        style: base,
        children: [
          TextSpan(
            text: line.field.isEmpty ? '•  ' : '${line.field}: ',
            style: strong,
          ),
          if (line.isChange) ...[
            TextSpan(
              text: line.before,
              style: base.copyWith(color: muted),
            ),
            TextSpan(
              text: '  →  ',
              style: base.copyWith(color: muted),
            ),
            TextSpan(text: line.after, style: strong),
          ] else
            TextSpan(text: line.before),
        ],
      ),
    );
  }
}
