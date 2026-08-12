import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/responsive/dpi_scale.dart';
import '../../../domain/purchasing/supplier.dart';
import '../../auth/viewmodel/auth_gate_view_model.dart';
import '../../theme/theme_data_factory.dart';
import '../viewmodel/suppliers_view_model.dart';

/// Formulario para crear o editar un suplidor. Valida el formato del
/// identificador fiscal según su tipo: RNC = 9 dígitos, cédula = 11 dígitos
/// (requisito F1 del PRD 6.1 — el 606 exige el par tipo+número correcto).
class SupplierFormView extends ConsumerStatefulWidget {
  const SupplierFormView({super.key, this.existing});

  /// Si no es null, edita ese suplidor; si es null, crea uno nuevo.
  final Supplier? existing;

  @override
  ConsumerState<SupplierFormView> createState() => _SupplierFormViewState();
}

class _SupplierFormViewState extends ConsumerState<SupplierFormView> {
  final _name = TextEditingController();
  final _rnc = TextEditingController();
  final _contactName = TextEditingController();
  final _phone = TextEditingController();
  final _whatsapp = TextEditingController();
  final _email = TextEditingController();
  final _address = TextEditingController();
  final _paymentDays = TextEditingController(text: '0');
  final _notes = TextEditingController();

  String _taxIdType = 'rnc';
  bool _isActive = true;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    if (e != null) {
      _name.text = e.name;
      _rnc.text = e.rnc ?? '';
      _contactName.text = e.contactName ?? '';
      _phone.text = e.phone ?? '';
      _whatsapp.text = e.whatsapp ?? '';
      _email.text = e.email ?? '';
      _address.text = e.address ?? '';
      _paymentDays.text = e.paymentTermsDays.toString();
      _notes.text = e.notes ?? '';
      _taxIdType = e.taxIdType ?? 'rnc';
      _isActive = e.isActive;
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _rnc.dispose();
    _contactName.dispose();
    _phone.dispose();
    _whatsapp.dispose();
    _email.dispose();
    _address.dispose();
    _paymentDays.dispose();
    _notes.dispose();
    super.dispose();
  }

  String? get _businessId =>
      ref.read(authGateViewModelProvider).profile?.businessId;

  void _snack(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  /// Valida el número fiscal según el tipo. Devuelve el mensaje de error o
  /// null si es válido. Vacío es válido: el suplidor informal existe.
  String? _validateTaxId(String value) {
    if (value.isEmpty) return null;
    final digits = value.replaceAll(RegExp(r'[^0-9]'), '');
    switch (_taxIdType) {
      case 'rnc':
        if (digits.length != 9) {
          return 'El RNC debe tener 9 dígitos (tiene ${digits.length}).';
        }
        return null;
      case 'cedula':
        if (digits.length != 11) {
          return 'La cédula debe tener 11 dígitos (tiene ${digits.length}).';
        }
        return null;
      default:
        return null; // pasaporte: formato libre
    }
  }

  Future<void> _save() async {
    final businessId = _businessId;
    if (businessId == null) return;

    final name = _name.text.trim();
    if (name.isEmpty) {
      _snack('Ponle un nombre al suplidor.');
      return;
    }
    final rawTaxId = _rnc.text.trim();
    final taxError = _validateTaxId(rawTaxId);
    if (taxError != null) {
      _snack(taxError);
      return;
    }
    // Se guarda solo el número normalizado (dígitos) para RNC/cédula.
    final taxId = _taxIdType == 'pasaporte'
        ? rawTaxId
        : rawTaxId.replaceAll(RegExp(r'[^0-9]'), '');

    final draft = SupplierDraft(
      name: name,
      rnc: taxId.isEmpty ? null : taxId,
      taxIdType: taxId.isEmpty ? null : _taxIdType,
      contactName: _contactName.text.trim(),
      phone: _phone.text.trim(),
      whatsapp: _whatsapp.text.trim(),
      email: _email.text.trim(),
      address: _address.text.trim(),
      paymentTermsDays: int.tryParse(_paymentDays.text.trim()) ?? 0,
      notes: _notes.text.trim(),
      isActive: _isActive,
    );

    final vm = ref.read(suppliersViewModelProvider.notifier);
    final ok = _isEdit
        ? await vm.update(businessId, widget.existing!.id, draft)
        : await vm.create(businessId, draft);
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop();
    } else {
      final err = ref.read(suppliersViewModelProvider).error;
      _snack(err ?? 'No se pudo guardar el suplidor.');
    }
  }

  Future<void> _delete() async {
    final businessId = _businessId;
    final existing = widget.existing;
    if (businessId == null || existing == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar suplidor'),
        content: Text(
          '¿Eliminar "${existing.name}"? Esta acción no se puede deshacer.',
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
        .read(suppliersViewModelProvider.notifier)
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
    final vm = ref.watch(suppliersViewModelProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? 'Editar suplidor' : 'Nuevo suplidor'),
        actions: [
          if (_isEdit)
            IconButton(
              tooltip: 'Eliminar suplidor',
              onPressed: vm.saving ? null : _delete,
              icon: Icon(Icons.delete_outline_rounded,
                  color: MangoThemeFactory.danger),
            ),
        ],
      ),
      body: ListView(
        padding: EdgeInsets.all(dpi.space(16)),
        children: [
          _sectionLabel(context, 'DATOS DEL SUPLIDOR'),
          TextField(
            controller: _name,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Nombre comercial',
              hintText: 'Ej. Distribuidora La Económica',
            ),
          ),
          SizedBox(height: dpi.space(14)),
          DropdownButtonFormField<String>(
            initialValue: _taxIdType,
            decoration: const InputDecoration(labelText: 'Tipo de identificación'),
            items: const [
              DropdownMenuItem(value: 'rnc', child: Text('RNC (9 dígitos)')),
              DropdownMenuItem(value: 'cedula', child: Text('Cédula (11 dígitos)')),
              DropdownMenuItem(value: 'pasaporte', child: Text('Pasaporte')),
            ],
            onChanged: (v) => setState(() => _taxIdType = v ?? 'rnc'),
          ),
          SizedBox(height: dpi.space(14)),
          TextField(
            controller: _rnc,
            keyboardType: _taxIdType == 'pasaporte'
                ? TextInputType.text
                : TextInputType.number,
            decoration: InputDecoration(
              labelText: _taxIdType == 'rnc'
                  ? 'RNC (opcional)'
                  : _taxIdType == 'cedula'
                      ? 'Cédula (opcional)'
                      : 'Pasaporte (opcional)',
              helperText: 'Necesario para que la compra entre al 606.',
            ),
          ),
          SizedBox(height: dpi.space(20)),

          _sectionLabel(context, 'CONTACTO'),
          TextField(
            controller: _contactName,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Persona de contacto (opcional)'),
          ),
          SizedBox(height: dpi.space(14)),
          TextField(
            controller: _phone,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(labelText: 'Teléfono (opcional)'),
          ),
          SizedBox(height: dpi.space(14)),
          TextField(
            controller: _whatsapp,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(
              labelText: 'WhatsApp (opcional)',
              helperText: 'Para enviarle las órdenes de compra.',
            ),
          ),
          SizedBox(height: dpi.space(14)),
          TextField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(labelText: 'Email (opcional)'),
          ),
          SizedBox(height: dpi.space(14)),
          TextField(
            controller: _address,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Dirección (opcional)'),
          ),
          SizedBox(height: dpi.space(20)),

          _sectionLabel(context, 'CONDICIONES'),
          TextField(
            controller: _paymentDays,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Término de pago (días)',
              helperText: '0 = contado',
            ),
          ),
          SizedBox(height: dpi.space(14)),
          TextField(
            controller: _notes,
            maxLines: 3,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Notas (opcional)'),
          ),
          if (_isEdit) ...[
            SizedBox(height: dpi.space(10)),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Suplidor activo'),
              subtitle: Text(
                _isActive
                    ? 'Disponible para nuevas órdenes de compra.'
                    : 'Oculto al crear órdenes de compra.',
                style: TextStyle(
                  fontSize: dpi.font(11.5),
                  color: MangoThemeFactory.mutedText(context),
                ),
              ),
              value: _isActive,
              activeThumbColor: MangoThemeFactory.success,
              onChanged: (v) => setState(() => _isActive = v),
            ),
          ],
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
                : Text(_isEdit ? 'Guardar cambios' : 'Crear suplidor'),
          ),
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
}
