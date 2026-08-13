import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/responsive/dpi_scale.dart';
import '../../../domain/catalog/admin_product.dart';
import '../../../domain/catalog/catalog_options.dart';
import '../../auth/viewmodel/auth_gate_view_model.dart';
import '../../purchasing/view/reception_scanner_page.dart';
import '../../theme/theme_data_factory.dart';
import '../viewmodel/products_admin_view_model.dart';

/// Formulario para crear o editar un producto (`menu_items`). Espejo del
/// diálogo "Elemento de Menú" del POS: mismos campos, mismas tablas
/// (menú, impuestos N:M, área de producción). Imagen, variaciones e
/// inventario se gestionan en el POS.
class ProductFormView extends ConsumerStatefulWidget {
  const ProductFormView({super.key, this.existing});

  /// Si no es null, edita ese producto; si es null, crea uno nuevo.
  final AdminProduct? existing;

  @override
  ConsumerState<ProductFormView> createState() => _ProductFormViewState();
}

class _ProductFormViewState extends ConsumerState<ProductFormView> {
  final _name = TextEditingController();
  final _description = TextEditingController();
  final _price = TextEditingController();
  final _cost = TextEditingController();
  final _sku = TextEditingController();
  final _barcode = TextEditingController();
  final _presentation = TextEditingController();

  String? _menuId;
  String? _categoryId;
  String _itemType = 'standard';
  String? _printAreaId;
  bool _taxEnabled = false;
  final Set<String> _taxIds = {};
  String _taxMode = 'exclusive';
  bool _isActive = true;

  bool get _isEdit => widget.existing != null;
  bool get _hasVariants => widget.existing?.hasVariants ?? false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    if (e != null) {
      _name.text = e.name;
      _description.text = e.description ?? '';
      _price.text = _trimNum(e.price);
      _cost.text = e.cost != null ? _trimNum(e.cost!) : '';
      _sku.text = e.sku ?? '';
      _barcode.text = e.barcode ?? '';
      _presentation.text = e.presentation ?? '';
      _menuId = e.menuId;
      _categoryId = e.categoryId;
      _itemType = e.itemType;
      _printAreaId = e.printAreaIds.isNotEmpty ? e.printAreaIds.first : null;
      _taxIds.addAll(e.taxIds);
      _taxEnabled = e.taxIds.isNotEmpty;
      _taxMode = e.taxMode;
      _isActive = e.isActive;
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _price.dispose();
    _cost.dispose();
    _sku.dispose();
    _barcode.dispose();
    _presentation.dispose();
    super.dispose();
  }

  static String _trimNum(double v) =>
      v.truncateToDouble() == v ? v.toInt().toString() : v.toString();

  static double? _parseNum(String text) {
    final t = text.trim().replaceAll(',', '.');
    if (t.isEmpty) return null;
    return double.tryParse(t);
  }

  String? get _businessId => ref.read(authGateViewModelProvider).profile?.businessId;

  void _snack(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  Future<void> _save() async {
    final businessId = _businessId;
    if (businessId == null) return;
    final vmState = ref.read(productsAdminViewModelProvider);

    final name = _name.text.trim();
    if (name.isEmpty) {
      _snack('Ponle un nombre al producto.');
      return;
    }
    // Igual que el POS: menú y categoría requeridos (menú solo si el negocio
    // tiene menús creados).
    if (vmState.menus.isNotEmpty && (_menuId == null || _menuId!.isEmpty)) {
      _snack('Selecciona el menú donde se publica el producto.');
      return;
    }
    if (_categoryId == null || _categoryId!.isEmpty) {
      _snack('Selecciona una categoría.');
      return;
    }
    double price;
    if (_hasVariants) {
      price = widget.existing!.price; // el precio vive en las variaciones
    } else {
      final parsed = _parseNum(_price.text);
      if (parsed == null || parsed < 0) {
        _snack('Ingresa un precio válido.');
        return;
      }
      price = parsed;
    }

    PrintAreaOption? area;
    for (final a in vmState.printAreas) {
      if (a.id == _printAreaId) area = a;
    }

    final draft = ProductDraft(
      name: name,
      price: price,
      categoryId: _categoryId,
      description:
          _description.text.trim().isEmpty ? null : _description.text.trim(),
      taxMode: _taxMode,
      isActive: _isActive,
      sku: _sku.text.trim().isEmpty ? null : _sku.text.trim(),
      barcode: _barcode.text.trim().isEmpty ? null : _barcode.text.trim(),
      cost: _parseNum(_cost.text),
      presentation:
          _presentation.text.trim().isEmpty ? null : _presentation.text.trim(),
      itemType: _itemType,
      printAreaCode: area?.code,
      menuId: _menuId,
      taxIds: _taxEnabled ? _taxIds.toList() : const [],
      printAreaIds: area != null ? [area.id] : const [],
    );

    final vm = ref.read(productsAdminViewModelProvider.notifier);
    final ok = _isEdit
        ? await vm.update(businessId, widget.existing!.id, draft)
        : await vm.create(businessId, draft);
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop();
    } else {
      final err = ref.read(productsAdminViewModelProvider).error;
      _snack(err ?? 'No se pudo guardar el producto.');
    }
  }

  Future<void> _delete() async {
    final businessId = _businessId;
    final existing = widget.existing;
    if (businessId == null || existing == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar producto'),
        content: Text(
          '¿Eliminar "${existing.name}" del catálogo? Esta acción no se puede deshacer.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: MangoThemeFactory.danger,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final error = await ref
        .read(productsAdminViewModelProvider.notifier)
        .delete(businessId, existing.id);
    if (!mounted) return;
    if (error == null) {
      Navigator.of(context).pop();
    } else {
      _snack(error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dpi = DpiScale.of(context);
    final vm = ref.watch(productsAdminViewModelProvider);

    final knownMenu =
        _menuId == null || vm.menus.any((m) => m.id == _menuId);
    final knownCategory =
        _categoryId == null || vm.categories.any((c) => c.id == _categoryId);

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? 'Editar producto' : 'Nuevo producto'),
        actions: [
          if (_isEdit)
            IconButton(
              tooltip: 'Eliminar producto',
              onPressed: vm.saving ? null : _delete,
              icon: Icon(Icons.delete_outline_rounded,
                  color: MangoThemeFactory.danger),
            ),
        ],
      ),
      body: ListView(
        padding: EdgeInsets.all(dpi.space(16)),
        children: [
          _sectionLabel(context, 'DATOS DEL ARTÍCULO'),
          TextField(
            controller: _name,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Nombre del artículo',
              hintText: 'Ej. Quesadilla',
            ),
          ),
          SizedBox(height: dpi.space(14)),
          TextField(
            controller: _description,
            maxLines: 3,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Descripción (opcional)',
            ),
          ),
          SizedBox(height: dpi.space(14)),
          if (vm.menus.isNotEmpty) ...[
            DropdownButtonFormField<String?>(
              initialValue: knownMenu ? _menuId : null,
              decoration: const InputDecoration(labelText: 'Menú'),
              items: [
                for (final m in vm.menus)
                  DropdownMenuItem<String?>(value: m.id, child: Text(m.name)),
              ],
              onChanged: (v) => setState(() => _menuId = v),
            ),
            SizedBox(height: dpi.space(14)),
          ],
          DropdownButtonFormField<String?>(
            initialValue: knownCategory ? _categoryId : null,
            decoration: const InputDecoration(labelText: 'Categoría'),
            items: [
              for (final c in vm.categories)
                DropdownMenuItem<String?>(value: c.id, child: Text(c.name)),
            ],
            onChanged: (v) => setState(() => _categoryId = v),
          ),
          SizedBox(height: dpi.space(20)),

          _sectionLabel(context, 'PRECIO Y REFERENCIAS'),
          TextField(
            controller: _price,
            enabled: !_hasVariants,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: 'Precio',
              prefixText: 'RD\$ ',
              helperText: _hasVariants
                  ? 'Este producto tiene variaciones; su precio se gestiona en el POS.'
                  : null,
            ),
          ),
          SizedBox(height: dpi.space(14)),
          TextField(
            controller: _cost,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Costo (opcional)',
              prefixText: 'RD\$ ',
            ),
          ),
          SizedBox(height: dpi.space(14)),
          TextField(
            controller: _sku,
            decoration: const InputDecoration(
              labelText: 'Referencia / SKU (opcional)',
            ),
          ),
          SizedBox(height: dpi.space(14)),
          TextField(
            controller: _barcode,
            decoration: InputDecoration(
              labelText: 'Código de barras (opcional)',
              suffixIcon: IconButton(
                tooltip: 'Escanear con cámara',
                icon: const Icon(Icons.qr_code_scanner_rounded),
                onPressed: () async {
                  final code = await Navigator.of(context).push<String>(
                    MaterialPageRoute(
                      builder: (_) =>
                          const ReceptionScannerPage(captureOnce: true),
                    ),
                  );
                  if (code != null && code.isNotEmpty) {
                    setState(() => _barcode.text = code);
                  }
                },
              ),
            ),
          ),
          SizedBox(height: dpi.space(14)),
          TextField(
            controller: _presentation,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Presentación (opcional)',
              hintText: 'Ej. Botella, Trago, Shot',
            ),
          ),
          SizedBox(height: dpi.space(14)),
          DropdownButtonFormField<String>(
            initialValue: _itemType,
            decoration: const InputDecoration(labelText: 'Tipo de elemento'),
            items: const [
              DropdownMenuItem(value: 'standard', child: Text('Producto normal')),
              DropdownMenuItem(value: 'combo', child: Text('Combo')),
              DropdownMenuItem(value: 'extra_only', child: Text('Extra / complemento')),
            ],
            onChanged: (v) => setState(() => _itemType = v ?? 'standard'),
          ),
          SizedBox(height: dpi.space(20)),

          _sectionLabel(context, 'ÁREA DE PRODUCCIÓN'),
          if (vm.printAreas.isEmpty)
            Text(
              'Este negocio no tiene áreas de impresión configuradas.',
              style: TextStyle(
                fontSize: dpi.font(12),
                color: MangoThemeFactory.mutedText(context),
              ),
            )
          else ...[
            Wrap(
              spacing: dpi.space(8),
              runSpacing: dpi.space(8),
              children: [
                for (final area in vm.printAreas)
                  FilterChip(
                    label: Text(area.name),
                    avatar: CircleAvatar(
                      backgroundColor:
                          _parseHex(area.color) ?? MangoThemeFactory.mango,
                      radius: dpi.scale(6),
                    ),
                    selected: _printAreaId == area.id,
                    onSelected: (sel) => setState(
                        () => _printAreaId = sel ? area.id : null),
                  ),
              ],
            ),
            if (_printAreaId == null) ...[
              SizedBox(height: dpi.space(6)),
              Text(
                'Sin área asignada: el producto no se ruteará a cocina/bar al enviarlo.',
                style: TextStyle(
                  fontSize: dpi.font(11),
                  color: MangoThemeFactory.warning,
                ),
              ),
            ],
          ],
          SizedBox(height: dpi.space(20)),

          _sectionLabel(context, 'IMPUESTOS'),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Aplicar impuestos'),
            value: _taxEnabled,
            onChanged: (v) => setState(() {
              _taxEnabled = v;
              if (!v) _taxIds.clear();
            }),
          ),
          if (_taxEnabled) ...[
            SizedBox(height: dpi.space(6)),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(
                    value: 'exclusive', label: Text('Exclusivo (+ al precio)')),
                ButtonSegment(
                    value: 'inclusive', label: Text('Incluido en el precio')),
              ],
              selected: {_taxMode},
              onSelectionChanged: (sel) =>
                  setState(() => _taxMode = sel.first),
            ),
            SizedBox(height: dpi.space(6)),
            if (vm.taxes.isEmpty)
              Padding(
                padding: EdgeInsets.symmetric(vertical: dpi.space(8)),
                child: Text(
                  'Este negocio no tiene impuestos configurados.',
                  style: TextStyle(
                    fontSize: dpi.font(12),
                    color: MangoThemeFactory.mutedText(context),
                  ),
                ),
              )
            else
              for (final tax in vm.taxes)
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: Text(tax.label),
                  value: _taxIds.contains(tax.id),
                  activeThumbColor: MangoThemeFactory.success,
                  onChanged: (v) => setState(() {
                    if (v) {
                      _taxIds.add(tax.id);
                    } else {
                      _taxIds.remove(tax.id);
                    }
                  }),
                ),
          ],
          SizedBox(height: dpi.space(10)),

          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Disponible'),
            subtitle: Text(
              _isActive ? 'Visible y disponible para la venta.' : 'Oculto en el POS.',
              style: TextStyle(
                fontSize: dpi.font(11.5),
                color: MangoThemeFactory.mutedText(context),
              ),
            ),
            value: _isActive,
            activeThumbColor: MangoThemeFactory.success,
            onChanged: (v) => setState(() => _isActive = v),
          ),
          SizedBox(height: dpi.space(22)),
          FilledButton(
            onPressed: vm.saving ? null : _save,
            style: FilledButton.styleFrom(
              backgroundColor: MangoThemeFactory.mango,
              padding: EdgeInsets.symmetric(vertical: dpi.space(14)),
            ),
            child: vm.saving
                ? SizedBox(
                    width: dpi.icon(18),
                    height: dpi.icon(18),
                    child: const CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : Text(_isEdit ? 'Guardar cambios' : 'Crear producto'),
          ),
          if (_isEdit) ...[
            SizedBox(height: dpi.space(10)),
            Text(
              'Imagen, variaciones e inventario se gestionan desde el POS.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: dpi.font(10.5),
                fontStyle: FontStyle.italic,
                color: MangoThemeFactory.mutedText(context),
              ),
            ),
          ],
          SizedBox(height: dpi.space(24)),
        ],
      ),
    );
  }

  Widget _sectionLabel(BuildContext context, String text) {
    final dpi = DpiScale.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: dpi.space(10)),
      child: Text(
        text,
        style: TextStyle(
          fontSize: dpi.font(10),
          fontWeight: FontWeight.w800,
          letterSpacing: 0.6,
          color: MangoThemeFactory.mutedText(context),
        ),
      ),
    );
  }

  static Color? _parseHex(String? hex) {
    if (hex == null) return null;
    final clean = hex.replaceFirst('#', '');
    if (clean.length != 6) return null;
    final value = int.tryParse(clean, radix: 16);
    if (value == null) return null;
    return Color(0xFF000000 | value);
  }
}
