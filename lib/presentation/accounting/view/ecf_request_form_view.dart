import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/di/providers.dart';
import '../../../core/responsive/dpi_scale.dart';
import '../../../domain/accounting/ecf_request.dart';
import '../../theme/theme_data_factory.dart';

/// Abre el formulario con que el dueño pide la facturación electrónica y
/// devuelve el resultado del envío, o null si salió sin enviar.
///
/// Va como pantalla pusheada, no como diálogo: son diez campos más la carga
/// del certificado, y en teléfono un `AlertDialog` deja la mitad del formulario
/// fuera de pantalla. Es una pantalla de creación, así que sigue el patrón de
/// las demás (orden de compra, recepción): scroll con secciones y los botones
/// pegados abajo sobre `SafeArea`.
Future<EcfRequestResult?> openEcfRequestForm(
  BuildContext context, {
  required String businessId,
  required EcfRequestStatus status,
}) {
  return Navigator.of(context).push<EcfRequestResult>(
    MaterialPageRoute(
      builder: (_) => EcfRequestFormView(businessId: businessId, status: status),
    ),
  );
}

class EcfRequestFormView extends ConsumerStatefulWidget {
  const EcfRequestFormView({
    super.key,
    required this.businessId,
    required this.status,
  });

  final String businessId;
  final EcfRequestStatus status;

  @override
  ConsumerState<EcfRequestFormView> createState() => _EcfRequestFormViewState();
}

class _EcfRequestFormViewState extends ConsumerState<EcfRequestFormView> {
  late final EcfRequestData _d = widget.status.data;
  late final _rnc = TextEditingController(text: _d.rnc ?? '');
  late final _legal = TextEditingController(text: _d.legalName ?? '');
  late final _trade = TextEditingController(text: _d.tradeName ?? '');
  late final _address = TextEditingController(text: _d.fiscalAddress ?? '');
  late final _province = TextEditingController(text: _d.province ?? '');
  late final _municipality = TextEditingController(text: _d.municipality ?? '');
  late final _email = TextEditingController(text: _d.email ?? '');
  late final _contactName =
      TextEditingController(text: widget.status.contactName ?? '');
  late final _contactPhone =
      TextEditingController(text: widget.status.contactPhone ?? '');
  final _password = TextEditingController();

  late bool _alreadyAuthorized = widget.status.alreadyAuthorized ?? false;
  bool _accept = false;
  bool _obscure = true;
  bool _sending = false;
  String? _certName;
  int _certSize = 0;
  Uint8List? _certBytes;
  String? _error;

  /// Un .p12 de firma digital pesa unos pocos KB. Más que esto no es un
  /// certificado, y atajarlo acá evita mandar un PDF por error.
  static const _maxCertBytes = 100 * 1024;

  @override
  void dispose() {
    for (final c in [
      _rnc, _legal, _trade, _address, _province, _municipality, _email,
      _contactName, _contactPhone, _password,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pickCertificate() async {
    try {
      // FileType.any a propósito: filtrar por extensión .p12 falla en algunos
      // Android/iOS que no conocen ese tipo. Se valida después.
      // `withData` porque el certificado se manda en base64, no por ruta: en
      // web no hay ruta, y en móvil evita un segundo paso de lectura.
      final result = await FilePicker.pickFiles(
        type: FileType.any,
        withData: true,
        dialogTitle: 'Certificado de firma digital (.p12)',
      );
      if (result == null || result.files.isEmpty) return;
      final file = result.files.first;
      final ext =
          file.name.contains('.') ? file.name.split('.').last.toLowerCase() : '';
      String? error;
      Uint8List? bytes;
      if (ext != 'p12' && ext != 'pfx') {
        error = 'El certificado tiene que ser un archivo .p12 o .pfx.';
      } else if (file.size > _maxCertBytes) {
        error = 'Ese archivo es demasiado grande para ser un certificado de firma.';
      } else {
        bytes = file.bytes;
        if (bytes == null || bytes.isEmpty) {
          error = 'No se pudo leer el archivo. Intenta elegirlo de nuevo.';
          bytes = null;
        }
      }
      if (!mounted) return;
      setState(() {
        _error = error;
        if (error == null) {
          _certName = file.name;
          _certSize = file.size;
          _certBytes = bytes;
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'No se pudo abrir el selector de archivos.');
    }
  }

  void _clearCertificate() {
    setState(() {
      _certName = null;
      _certSize = 0;
      _certBytes = null;
    });
  }

  String? _validate() {
    final rnc = _rnc.text.replaceAll(RegExp(r'\D'), '');
    if (rnc.length != 9 && rnc.length != 11) {
      return 'El RNC debe tener 9 dígitos (u 11 si es cédula).';
    }
    if (_legal.text.trim().isEmpty) return 'Falta la razón social.';
    if (_address.text.trim().isEmpty) return 'Falta la dirección fiscal.';
    if (_contactName.text.trim().isEmpty) return 'Falta la persona de contacto.';
    if (_contactPhone.text.replaceAll(RegExp(r'\D'), '').length < 10) {
      return 'El teléfono de contacto debe incluir el código de área.';
    }
    if (_certBytes == null) return 'Falta tu certificado de firma digital (.p12).';
    if (_password.text.isEmpty) return 'Falta la contraseña del certificado.';
    if (!_accept) return 'Debes autorizar a MangoPOS para continuar.';
    return null;
  }

  Future<void> _submit() async {
    final error = _validate();
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    setState(() {
      _sending = true;
      _error = null;
    });

    String? clean(TextEditingController c) {
      final t = c.text.trim();
      return t.isEmpty ? null : t;
    }

    try {
      final result = await ref.read(ecfRequestServiceProvider).submit(
            widget.businessId,
            EcfRequestSubmission(
              data: EcfRequestData(
                rnc: _rnc.text.replaceAll(RegExp(r'\D'), ''),
                legalName: clean(_legal),
                tradeName: clean(_trade),
                fiscalAddress: clean(_address),
                province: clean(_province),
                municipality: clean(_municipality),
                email: clean(_email),
              ),
              contactName: _contactName.text.trim(),
              contactPhone: _contactPhone.text.trim(),
              alreadyAuthorized: _alreadyAuthorized,
              certificateFilename: _certName!,
              certificateBytes: _certBytes!,
              certificatePassword: _password.text,
            ),
          );
      if (mounted) Navigator.of(context).pop(result);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _error = e is EcfRequestException
            ? e.message
            : 'No se pudo enviar la solicitud. Revisa tu conexión e intenta de nuevo.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final dpi = DpiScale.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Facturación electrónica'),
        centerTitle: false,
      ),
      bottomNavigationBar: _BottomBar(
        error: _error,
        sending: _sending,
        onCancel: _sending ? null : () => Navigator.of(context).pop(),
        onSubmit: _sending ? null : _submit,
      ),
      body: SafeArea(
        bottom: false,
        child: Center(
          // En web el formulario no se estira a lo ancho de la pantalla: una
          // columna de lectura cómoda, centrada, como en cualquier alta.
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: dpi.scale(620)),
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(
                  parent: BouncingScrollPhysics()),
              padding: EdgeInsets.fromLTRB(
                  dpi.space(16), dpi.space(16), dpi.space(16), dpi.space(24)),
              children: [
                const _IntroCard(),
                SizedBox(height: dpi.space(20)),

                _SectionHeader(
                  'DATOS DE TU EMPRESA',
                  hint: 'Tal como aparecen en la DGII',
                ),
                _field(_rnc, 'RNC o cédula', keyboard: TextInputType.number),
                _field(_legal, 'Razón social'),
                _field(_trade, 'Nombre comercial (opcional)'),
                _field(_address, 'Dirección fiscal', maxLength: 100),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: _field(_province, 'Provincia')),
                    SizedBox(width: dpi.space(12)),
                    Expanded(child: _field(_municipality, 'Municipio')),
                  ],
                ),
                _field(_email, 'Correo', keyboard: TextInputType.emailAddress),
                SizedBox(height: dpi.space(14)),

                _SectionHeader(
                  'CONTACTO',
                  hint: 'Con quién coordinamos la certificación',
                ),
                _field(_contactName, 'Nombre'),
                _field(_contactPhone, 'Teléfono',
                    keyboard: TextInputType.phone),
                SizedBox(height: dpi.space(4)),
                _SoftSwitchRow(
                  icon: Icons.workspace_premium_outlined,
                  title: 'Ya soy emisor electrónico autorizado',
                  subtitle: 'Si no lo eres, MangoPOS te guía en la certificación.',
                  value: _alreadyAuthorized,
                  onChanged: _sending
                      ? null
                      : (v) => setState(() => _alreadyAuthorized = v),
                ),
                SizedBox(height: dpi.space(20)),

                _SectionHeader(
                  'CERTIFICADO DE FIRMA DIGITAL',
                  hint: 'A nombre de la empresa o su representante legal',
                ),
                _CertificateCard(
                  filename: _certName,
                  sizeBytes: _certSize,
                  enabled: !_sending,
                  onPick: _pickCertificate,
                  onClear: _clearCertificate,
                ),
                SizedBox(height: dpi.space(12)),
                TextField(
                  controller: _password,
                  obscureText: _obscure,
                  enabled: !_sending,
                  decoration: InputDecoration(
                    labelText: 'Contraseña del certificado',
                    suffixIcon: IconButton(
                      tooltip: _obscure ? 'Mostrar' : 'Ocultar',
                      onPressed: () => setState(() => _obscure = !_obscure),
                      icon: Icon(
                        _obscure
                            ? Icons.visibility_rounded
                            : Icons.visibility_off_rounded,
                        size: dpi.icon(18),
                      ),
                    ),
                  ),
                ),
                SizedBox(height: dpi.space(14)),
                _ConsentRow(
                  value: _accept,
                  onChanged:
                      _sending ? null : (v) => setState(() => _accept = v),
                ),
                SizedBox(height: dpi.space(12)),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.lock_outline_rounded,
                        size: dpi.icon(14),
                        color: MangoThemeFactory.mutedText(context)),
                    SizedBox(width: dpi.space(8)),
                    Expanded(
                      child: Text(
                        'MangoPOS no guarda el certificado ni la contraseña: '
                        'viajan al proveedor de facturación electrónica en la '
                        'misma petición.',
                        style: TextStyle(
                          fontSize: dpi.font(11.5),
                          color: MangoThemeFactory.mutedText(context),
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _field(
    TextEditingController c,
    String label, {
    TextInputType? keyboard,
    int? maxLength,
  }) {
    final dpi = DpiScale.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: dpi.space(12)),
      child: TextField(
        controller: c,
        enabled: !_sending,
        keyboardType: keyboard,
        maxLength: maxLength,
        textCapitalization: keyboard == null
            ? TextCapitalization.words
            : TextCapitalization.none,
        inputFormatters: keyboard == TextInputType.number
            ? [FilteringTextInputFormatter.allow(RegExp(r'[0-9-]'))]
            : null,
        decoration: InputDecoration(labelText: label, counterText: ''),
      ),
    );
  }
}

/// Barra inferior fija: el motivo por el que no se puede enviar queda siempre
/// a la vista, en vez de perderse al final de un formulario largo.
class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.error,
    required this.sending,
    required this.onCancel,
    required this.onSubmit,
  });

  final String? error;
  final bool sending;
  final VoidCallback? onCancel;
  final VoidCallback? onSubmit;

  @override
  Widget build(BuildContext context) {
    final dpi = DpiScale.of(context);
    return SafeArea(
      child: Container(
        padding: EdgeInsets.fromLTRB(
            dpi.space(16), dpi.space(10), dpi.space(16), dpi.space(12)),
        decoration: BoxDecoration(
          color: MangoThemeFactory.cardColor(context),
          border: Border(
            top: BorderSide(color: MangoThemeFactory.borderColor(context)),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (error != null) ...[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.error_outline_rounded,
                      size: dpi.icon(16), color: MangoThemeFactory.danger),
                  SizedBox(width: dpi.space(8)),
                  Expanded(
                    child: Text(
                      error!,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: dpi.font(12),
                        color: MangoThemeFactory.danger,
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              ),
              SizedBox(height: dpi.space(10)),
            ],
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: onCancel,
                    style: OutlinedButton.styleFrom(
                      padding: EdgeInsets.symmetric(vertical: dpi.space(13)),
                    ),
                    child: const Text('Cancelar'),
                  ),
                ),
                SizedBox(width: dpi.space(10)),
                Expanded(
                  flex: 2,
                  child: FilledButton(
                    onPressed: onSubmit,
                    style: FilledButton.styleFrom(
                      padding: EdgeInsets.symmetric(vertical: dpi.space(13)),
                    ),
                    child: sending
                        ? SizedBox(
                            width: dpi.scale(18),
                            height: dpi.scale(18),
                            child: const CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : const Text('Enviar solicitud'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _IntroCard extends StatelessWidget {
  const _IntroCard();

  @override
  Widget build(BuildContext context) {
    final dpi = DpiScale.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: EdgeInsets.all(dpi.space(14)),
      decoration: BoxDecoration(
        color: MangoThemeFactory.cardColor(context),
        borderRadius: BorderRadius.circular(dpi.radius(14)),
        border: Border.all(color: MangoThemeFactory.borderColor(context)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: dpi.scale(38),
            height: dpi.scale(38),
            decoration: BoxDecoration(
              color: MangoThemeFactory.mango
                  .withValues(alpha: isDark ? 0.2 : 0.1),
              borderRadius: BorderRadius.circular(dpi.radius(10)),
            ),
            child: Icon(Icons.verified_outlined,
                color: MangoThemeFactory.mango, size: dpi.icon(20)),
          ),
          SizedBox(width: dpi.space(12)),
          Expanded(
            child: Text(
              'MangoPOS registra tu empresa con su proveedor de facturación '
              'electrónica y te acompaña en la certificación ante la DGII.',
              style: TextStyle(fontSize: dpi.font(12.5), height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.label, {this.hint});

  final String label;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final dpi = DpiScale.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: dpi.space(10)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: dpi.font(11),
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
              color: MangoThemeFactory.mutedText(context),
            ),
          ),
          if (hint != null) ...[
            SizedBox(height: dpi.space(2)),
            Text(
              hint!,
              style: TextStyle(
                fontSize: dpi.font(11),
                color: MangoThemeFactory.mutedText(context),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Carga del certificado: card blanda con dos estados, vacío y con archivo.
/// Que el archivo elegido se vea con su nombre y peso es lo que da confianza
/// de que subió el correcto antes de mandar la contraseña.
class _CertificateCard extends StatelessWidget {
  const _CertificateCard({
    required this.filename,
    required this.sizeBytes,
    required this.enabled,
    required this.onPick,
    required this.onClear,
  });

  final String? filename;
  final int sizeBytes;
  final bool enabled;
  final VoidCallback onPick;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final dpi = DpiScale.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final picked = filename != null;
    final accent =
        picked ? MangoThemeFactory.success : MangoThemeFactory.mutedText(context);

    return Container(
      decoration: BoxDecoration(
        color: MangoThemeFactory.cardColor(context),
        borderRadius: BorderRadius.circular(dpi.radius(14)),
        border: Border.all(
          color: picked
              ? MangoThemeFactory.success
              : MangoThemeFactory.borderColor(context),
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(dpi.radius(14)),
          onTap: enabled ? onPick : null,
          child: Padding(
            padding: EdgeInsets.all(dpi.space(14)),
            child: Row(
              children: [
                Container(
                  width: dpi.scale(38),
                  height: dpi.scale(38),
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: isDark ? 0.2 : 0.1),
                    borderRadius: BorderRadius.circular(dpi.radius(10)),
                  ),
                  child: Icon(
                    picked
                        ? Icons.check_circle_rounded
                        : Icons.upload_file_rounded,
                    color: accent,
                    size: dpi.icon(20),
                  ),
                ),
                SizedBox(width: dpi.space(12)),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        picked ? filename! : 'Elegir certificado',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: dpi.font(13.5),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      SizedBox(height: dpi.space(2)),
                      Text(
                        picked
                            ? '${_formatSize(sizeBytes)} · toca para cambiarlo'
                            : 'Archivo .p12 o .pfx',
                        style: TextStyle(
                          fontSize: dpi.font(11),
                          color: MangoThemeFactory.mutedText(context),
                        ),
                      ),
                    ],
                  ),
                ),
                if (picked)
                  IconButton(
                    tooltip: 'Quitar',
                    onPressed: enabled ? onClear : null,
                    icon: Icon(Icons.close_rounded, size: dpi.icon(18)),
                  )
                else
                  Icon(Icons.chevron_right_rounded,
                      color: MangoThemeFactory.mutedText(context)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    return '${(bytes / 1024).toStringAsFixed(1)} KB';
  }
}

/// Fila de interruptor como card blanda. `SwitchListTile` pelado sobre el
/// fondo del scaffold rompe el lenguaje del resto de la pantalla.
class _SoftSwitchRow extends StatelessWidget {
  const _SoftSwitchRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final dpi = DpiScale.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent =
        value ? MangoThemeFactory.success : MangoThemeFactory.mutedText(context);
    return Container(
      decoration: BoxDecoration(
        color: MangoThemeFactory.cardColor(context),
        borderRadius: BorderRadius.circular(dpi.radius(14)),
        border: Border.all(color: MangoThemeFactory.borderColor(context)),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(dpi.radius(14)),
          onTap: onChanged == null ? null : () => onChanged!(!value),
          child: Padding(
            padding: EdgeInsets.all(dpi.space(12)),
            child: Row(
              children: [
                Container(
                  width: dpi.scale(36),
                  height: dpi.scale(36),
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: isDark ? 0.2 : 0.1),
                    borderRadius: BorderRadius.circular(dpi.radius(10)),
                  ),
                  child: Icon(icon, color: accent, size: dpi.icon(19)),
                ),
                SizedBox(width: dpi.space(12)),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: dpi.font(13),
                          fontWeight: FontWeight.w700,
                          height: 1.25,
                        ),
                      ),
                      SizedBox(height: dpi.space(2)),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: dpi.font(11),
                          color: MangoThemeFactory.mutedText(context),
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
                Switch(value: value, onChanged: onChanged),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Autorización para usar el certificado. Va como card aparte y no como
/// `CheckboxListTile` suelto porque es la casilla que desbloquea el envío.
class _ConsentRow extends StatelessWidget {
  const _ConsentRow({required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final dpi = DpiScale.of(context);
    return Container(
      decoration: BoxDecoration(
        color: MangoThemeFactory.cardColor(context),
        borderRadius: BorderRadius.circular(dpi.radius(14)),
        border: Border.all(
          color: value
              ? MangoThemeFactory.mango
              : MangoThemeFactory.borderColor(context),
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(dpi.radius(14)),
          onTap: onChanged == null ? null : () => onChanged!(!value),
          child: Padding(
            padding: EdgeInsets.fromLTRB(
                dpi.space(6), dpi.space(8), dpi.space(14), dpi.space(8)),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Checkbox(
                  value: value,
                  onChanged: onChanged == null
                      ? null
                      : (v) => onChanged!(v ?? false),
                ),
                SizedBox(width: dpi.space(4)),
                Expanded(
                  child: Text(
                    'Autorizo a MangoPOS a registrar mi empresa con su proveedor '
                    'de facturación electrónica usando este certificado.',
                    style: TextStyle(fontSize: dpi.font(12.5), height: 1.35),
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
