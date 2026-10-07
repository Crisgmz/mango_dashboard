import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/responsive/dpi_scale.dart';
import '../../../domain/catalog/product_category.dart';
import '../../auth/viewmodel/auth_gate_view_model.dart';
import '../../theme/theme_data_factory.dart';
import '../../widgets/soft_admin_parts.dart';
import '../viewmodel/categories_admin_view_model.dart';

/// Categorías del menú (tabla `categories`, la misma que usa el POS): crear,
/// renombrar, color del botón, mostrar/ocultar en ventas, ordenar y eliminar.
class CategoriesAdminView extends ConsumerStatefulWidget {
  const CategoriesAdminView({super.key});

  @override
  ConsumerState<CategoriesAdminView> createState() =>
      _CategoriesAdminViewState();
}

class _CategoriesAdminViewState extends ConsumerState<CategoriesAdminView> {
  String? get _businessId =>
      ref.read(authGateViewModelProvider).profile?.businessId;

  CategoriesAdminViewModel get _vm =>
      ref.read(categoriesAdminViewModelProvider.notifier);

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

  Future<void> _create() async {
    final id = _businessId;
    if (id == null) return;
    final result = await showDialog<_CategoryDialogResult>(
      context: context,
      builder: (_) => _CategoryDialog(
        supportsColor: ref.read(categoriesAdminViewModelProvider).supportsColor,
      ),
    );
    if (result == null || result.delete) return;
    final error = await _vm.create(id, name: result.name, color: result.color);
    _snack(error ?? 'Categoría creada.');
  }

  Future<void> _edit(ProductCategory category) async {
    final id = _businessId;
    if (id == null) return;
    final state = ref.read(categoriesAdminViewModelProvider);
    final result = await showDialog<_CategoryDialogResult>(
      context: context,
      builder: (_) => _CategoryDialog(
        existing: category,
        productCount: state.productCounts[category.id] ?? 0,
        supportsColor: state.supportsColor,
      ),
    );
    if (result == null) return;
    if (result.delete) {
      await _confirmDelete(category);
      return;
    }
    final error = await _vm.update(
      id,
      category,
      name: result.name,
      color: result.color,
    );
    _snack(error ?? 'Categoría guardada.');
  }

  Future<void> _confirmDelete(ProductCategory category) async {
    final id = _businessId;
    if (id == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar categoría'),
        content: Text(
          '¿Eliminar "${category.name}"? Esta acción no se puede deshacer.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: MangoThemeFactory.danger,
            ),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final error = await _vm.delete(id, category);
    _snack(error ?? 'Categoría eliminada.');
  }

  @override
  Widget build(BuildContext context) {
    final dpi = DpiScale.of(context);
    final vm = ref.watch(categoriesAdminViewModelProvider);
    final id = _businessId;

    ref.listen<CategoriesAdminState>(categoriesAdminViewModelProvider, (
      prev,
      next,
    ) {
      if (next.error != null && next.error != prev?.error) _snack(next.error!);
    });

    return Scaffold(
      appBar: AppBar(title: const Text('Categorías')),
      floatingActionButton: (id == null || vm.categories.isEmpty)
          ? null
          : FloatingActionButton.extended(
              onPressed: vm.saving ? null : _create,
              backgroundColor: MangoThemeFactory.mango,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Nueva categoría'),
            ),
      body: id == null
          ? const Center(child: Text('No hay un negocio activo.'))
          : RefreshIndicator(
              onRefresh: () => _vm.refresh(id),
              child: _body(context, dpi, vm, id),
            ),
    );
  }

  Widget _body(
    BuildContext context,
    DpiScale dpi,
    CategoriesAdminState vm,
    String businessId,
  ) {
    final padding = EdgeInsets.fromLTRB(
      dpi.space(16),
      dpi.space(8),
      dpi.space(16),
      dpi.space(96),
    );
    if (vm.isLoading && vm.categories.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (vm.categories.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: padding,
        children: [
          SizedBox(height: dpi.space(40)),
          SoftEmptyState(
            icon: Icons.category_outlined,
            title: 'Aún no hay categorías',
            message:
                'Crea la primera para agrupar los productos en la pantalla de ventas del POS.',
            action: FilledButton.icon(
              onPressed: vm.saving ? null : _create,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Crear categoría'),
            ),
          ),
        ],
      );
    }

    return ReorderableListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: padding,
      buildDefaultDragHandles: false,
      header: const SoftSectionHeader(
        label: 'CATEGORÍAS',
        hint: 'Arrastra ⠿ para cambiar el orden en el POS. Toca para editar.',
      ),
      itemCount: vm.categories.length,
      onReorderItem: (oldIndex, newIndex) =>
          _vm.reorder(businessId, oldIndex, newIndex),
      itemBuilder: (context, index) {
        final c = vm.categories[index];
        final count = vm.productCounts[c.id] ?? 0;
        final color = parseHexColor(c.color);
        return KeyedSubtree(
          key: ValueKey(c.id),
          child: SoftRowCard(
            onTap: vm.saving ? null : () => _edit(c),
            leading: SoftInitialAvatar(
              text: c.name.isEmpty ? '?' : c.name[0].toUpperCase(),
              color: color,
            ),
            title: c.name,
            subtitle: [
              count == 1 ? '1 producto' : '$count productos',
              c.isActive ? 'Visible en el POS' : 'Oculta en el POS',
            ].join(' · '),
            subtitleColor: c.isActive ? null : MangoThemeFactory.danger,
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (vm.savingIds.contains(c.id))
                  SizedBox(
                    width: dpi.icon(20),
                    height: dpi.icon(20),
                    child: const CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  Switch(
                    value: c.isActive,
                    onChanged: (v) => _vm.toggleActive(c, v),
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
}

class _CategoryDialogResult {
  const _CategoryDialogResult.save(this.name, this.color) : delete = false;
  const _CategoryDialogResult.delete() : name = '', color = null, delete = true;

  final String name;
  final String? color;
  final bool delete;
}

/// Crear/editar: nombre y color del botón en el POS. Al editar, ofrece
/// eliminar (solo si no tiene productos).
class _CategoryDialog extends StatefulWidget {
  const _CategoryDialog({
    this.existing,
    this.productCount = 0,
    required this.supportsColor,
  });

  final ProductCategory? existing;
  final int productCount;
  final bool supportsColor;

  @override
  State<_CategoryDialog> createState() => _CategoryDialogState();
}

class _CategoryDialogState extends State<_CategoryDialog> {
  late final TextEditingController _name = TextEditingController(
    text: widget.existing?.name ?? '',
  );
  late String? _color = widget.existing?.color;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _save() {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Escribe el nombre.');
      return;
    }
    Navigator.pop(context, _CategoryDialogResult.save(name, _color));
  }

  @override
  Widget build(BuildContext context) {
    final dpi = DpiScale.of(context);
    final existing = widget.existing;
    final muted = MangoThemeFactory.mutedText(context);

    return AlertDialog(
      title: Text(existing?.name ?? 'Nueva categoría'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _name,
              autofocus: existing == null,
              textCapitalization: TextCapitalization.sentences,
              onSubmitted: (_) => _save(),
              decoration: InputDecoration(
                labelText: 'Nombre',
                hintText: 'Ej. Bebidas',
                errorText: _error,
              ),
            ),
            if (widget.supportsColor) ...[
              SizedBox(height: dpi.space(16)),
              Text(
                'Color del botón en el POS',
                style: TextStyle(fontSize: dpi.font(12), color: muted),
              ),
              SizedBox(height: dpi.space(8)),
              Wrap(
                spacing: dpi.space(8),
                runSpacing: dpi.space(8),
                children: [
                  _ColorChoice(
                    color: null,
                    selected: _color == null,
                    onTap: () => setState(() => _color = null),
                  ),
                  for (final hex in kCategoryColorPalette)
                    _ColorChoice(
                      color: parseHexColor(hex),
                      selected: _color?.toUpperCase() == hex,
                      onTap: () => setState(() => _color = hex),
                    ),
                ],
              ),
            ],
            if (existing != null) ...[
              SizedBox(height: dpi.space(16)),
              if (widget.productCount > 0)
                Text(
                  'Tiene ${widget.productCount} producto${widget.productCount == 1 ? '' : 's'}: '
                  'para eliminarla, muévelos a otra categoría o desactívala con el interruptor.',
                  style: TextStyle(fontSize: dpi.font(11.5), color: muted),
                )
              else
                TextButton.icon(
                  onPressed: () => Navigator.pop(
                    context,
                    const _CategoryDialogResult.delete(),
                  ),
                  style: TextButton.styleFrom(
                    foregroundColor: MangoThemeFactory.danger,
                  ),
                  icon: Icon(Icons.delete_outline_rounded, size: dpi.icon(18)),
                  label: const Text('Eliminar categoría'),
                ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _save,
          child: Text(existing == null ? 'Crear' : 'Guardar'),
        ),
      ],
    );
  }
}

class _ColorChoice extends StatelessWidget {
  const _ColorChoice({
    required this.color,
    required this.selected,
    required this.onTap,
  });

  /// null = sin color.
  final Color? color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final dpi = DpiScale.of(context);
    final size = dpi.scale(32);
    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: color ?? MangoThemeFactory.altSurface(context),
          shape: BoxShape.circle,
          border: Border.all(
            color: selected
                ? MangoThemeFactory.textColor(context)
                : MangoThemeFactory.borderColor(context),
            width: selected ? 2 : 1,
          ),
        ),
        child: selected
            ? Icon(
                Icons.check_rounded,
                size: dpi.icon(16),
                color: color == null
                    ? MangoThemeFactory.textColor(context)
                    : Colors.white,
              )
            : (color == null
                  ? Icon(
                      Icons.block_rounded,
                      size: dpi.icon(14),
                      color: MangoThemeFactory.mutedText(context),
                    )
                  : null),
      ),
    );
  }
}
