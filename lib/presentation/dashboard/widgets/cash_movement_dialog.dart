import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/di/providers.dart';
import '../../../core/formatters/mango_formatters.dart';
import '../../../core/responsive/dpi_scale.dart';
import '../../../domain/dashboard/dashboard_models.dart';
import '../../theme/theme_data_factory.dart';
import '../viewmodel/cash_register_view_model.dart';

/// Los tres movimientos manuales de caja, igual que en el POS.
const cashMovementDeposit = 'deposit';
const cashMovementWithdrawal = 'withdrawal';
const cashMovementExpense = 'expense';

/// Etiqueta en minúscula del tipo, con las mismas palabras del POS:
/// ingreso (deposit), retiro (withdrawal), gasto (expense).
String cashMovementTypeLabel(String type) {
  switch (type) {
    case cashMovementDeposit:
      return 'ingreso';
    case cashMovementWithdrawal:
      return 'retiro';
    case cashMovementExpense:
      return 'gasto';
    default:
      return 'movimiento';
  }
}

/// Registra un movimiento manual de caja (`cash_transactions`: ingreso,
/// retiro o gasto) en una caja ABIERTA del negocio, desde el dashboard.
///
/// Es el mismo RPC que usa el POS (`fn_cash_transaction_create`), con la misma
/// razón obligatoria del catálogo del negocio, así que el movimiento pesa en el
/// cierre igual que si lo hubiera hecho el cajero: el ingreso suma al efectivo
/// esperado, el retiro y el gasto lo restan. Por eso exige una caja abierta:
/// sin sesión no hay gaveta que mover, y el diálogo lo explica en vez de
/// inventarse una.
///
/// Devuelve el tipo registrado (`deposit | withdrawal | expense`), o null si se
/// canceló.
Future<String?> showCashMovementDialog({
  required BuildContext context,
  required String businessId,
  RegisterSession? session,
  String initialType = cashMovementDeposit,
}) {
  return showDialog<String>(
    context: context,
    builder: (_) => _CashMovementDialog(
      businessId: businessId,
      presetSession: session,
      initialType: initialType,
    ),
  );
}

class _CashMovementDialog extends ConsumerStatefulWidget {
  const _CashMovementDialog({
    required this.businessId,
    required this.initialType,
    this.presetSession,
  });

  final String businessId;
  final String initialType;

  /// Caja ya conocida por el llamador (detalle de una caja abierta). Si viene,
  /// no se consultan las demás.
  final RegisterSession? presetSession;

  @override
  ConsumerState<_CashMovementDialog> createState() =>
      _CashMovementDialogState();
}

class _CashMovementDialogState extends ConsumerState<_CashMovementDialog> {
  final _amount = TextEditingController();
  final _note = TextEditingController();

  late String _type;
  bool _loading = true;
  bool _submitting = false;
  String? _loadError;
  String? _error;
  bool _submitted = false;

  List<RegisterSession> _sessions = const [];

  /// Catálogo completo del negocio; se filtra por tipo al vuelo para que
  /// cambiar de ingreso a gasto no cueste otra consulta.
  List<CashMovementReason> _allReasons = const [];
  RegisterSession? _session;
  CashMovementReason? _reason;

  @override
  void initState() {
    super.initState();
    _type = widget.initialType;
    _session = widget.presetSession;
    _amount.addListener(() => setState(() {}));
    _load();
  }

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final service = ref.read(cashRegisterDataServiceProvider);
    try {
      final sessions = widget.presetSession != null
          ? [widget.presetSession!]
          : await service.loadOpenSessions(widget.businessId);
      final reasons = await service.loadMovementReasons(
        businessId: widget.businessId,
      );
      if (!mounted) return;
      setState(() {
        _loading = false;
        _sessions = sessions;
        _allReasons = reasons;
        _session ??= sessions.length == 1 ? sessions.first : null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = 'No se pudieron cargar las cajas abiertas.';
      });
    }
  }

  /// Razones que aplican al tipo elegido: las suyas más las universales
  /// (`applies_to` null), igual que el desplegable del POS.
  List<CashMovementReason> get _reasons => _allReasons
      .where((r) => r.appliesTo == null || r.appliesTo == _type)
      .toList(growable: false);

  /// RD$ escribe los miles con coma y los centavos con punto ("10,500.50").
  /// Debajo del campo se muestra el monto ya formateado para que nadie
  /// confirme a ciegas lo que el parser entendió.
  double? get _parsedAmount =>
      MangoFormatters.parsePositiveAmount(_amount.text);

  bool get _noteRequired => _reason?.needsNote ?? false;

  void _selectType(String type) {
    if (type == _type) return;
    setState(() {
      _type = type;
      // La razón pertenece a un tipo: al cambiar de pestaña deja de valer.
      _reason = null;
      _error = null;
    });
  }

  Future<void> _submit() async {
    setState(() {
      _submitted = true;
      _error = null;
    });
    final session = _session;
    final reason = _reason;
    final amount = _parsedAmount;
    if (session == null || reason == null || amount == null) return;
    if (_noteRequired && _note.text.trim().isEmpty) return;

    // Razón marcada como `requires_pin`: se pide la aprobación de entrada,
    // como hace el POS, en vez de gastar un viaje al servidor para que la
    // rechace.
    var approve = false;
    if (reason.requiresPin) {
      final approved = await _confirmSupervisorApproval(reason);
      if (!mounted || !approved) return;
      approve = true;
    }

    setState(() => _submitting = true);
    var result = await _register(session, reason, amount, approve: approve);
    if (!mounted) return;

    // El umbral monetario del negocio no se ve desde el catálogo: solo se
    // sabe cuando la RPC lo reclama. Se pide la aprobación y se reintenta una
    // vez, igual que el POS.
    if (result.needsApproval && !approve) {
      final approved = await _confirmSupervisorApproval(reason);
      if (!mounted) return;
      if (!approved) {
        setState(() => _submitting = false);
        return;
      }
      result = await _register(session, reason, amount, approve: true);
      if (!mounted) return;
    }
    _finish(result);
  }

  Future<CashMovementResult> _register(
    RegisterSession session,
    CashMovementReason reason,
    double amount, {
    required bool approve,
  }) {
    final note = _note.text.trim();
    return ref
        .read(cashRegisterViewModelProvider.notifier)
        .registerMovement(
          sessionId: session.id,
          type: _type,
          amount: amount,
          reasonCode: reason.code,
          description: note.isEmpty ? null : note,
          approveAsSupervisor: approve,
          businessId: widget.businessId,
        );
  }

  void _finish(CashMovementResult result) {
    if (result.isOk) {
      Navigator.of(context).pop(_type);
      return;
    }
    setState(() {
      _submitting = false;
      _error =
          result.error ??
          'No se pudo registrar el ${cashMovementTypeLabel(_type)}.';
    });
  }

  /// El POS pide PIN de supervisor para estas razones/montos. Acá el owner ya
  /// está autenticado, así que la firma es su propio usuario — pero se le dice
  /// en la cara que está aprobando, y queda en `approved_by`.
  Future<bool> _confirmSupervisorApproval(CashMovementReason reason) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Requiere aprobación'),
        content: Text(
          '"${reason.label}" necesita firma de supervisor. Si continúas, el '
          '${cashMovementTypeLabel(_type)} queda registrado y aprobado con tu '
          'usuario.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Aprobar y registrar'),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const AlertDialog(
        title: Text('Registrar movimiento'),
        content: SizedBox(
          height: 72,
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }
    if (_loadError != null) return _blocked(_loadError!);
    if (_sessions.isEmpty) {
      return _blocked(
        'No hay ninguna caja abierta en este negocio. Los movimientos manuales '
        'entran y salen de una caja abierta y cuadran en su cierre, así que '
        'primero hay que abrirla en el punto de venta.',
      );
    }
    if (_allReasons.isEmpty) {
      return _blocked(
        'Este negocio no tiene razones de caja configuradas, y el movimiento '
        'las exige. Configúralas en el punto de venta y vuelve a intentar.',
      );
    }
    return _form(context);
  }

  /// Caso sin salida (sin caja abierta, sin catálogo, sin red): se explica qué
  /// falta en vez de mostrar un formulario que va a fallar al enviar.
  Widget _blocked(String message) {
    return AlertDialog(
      title: const Text('Registrar movimiento'),
      content: Text(message, style: Theme.of(context).textTheme.bodyMedium),
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Entendido'),
        ),
      ],
    );
  }

  Widget _form(BuildContext context) {
    final dpi = DpiScale.of(context);
    final amount = _parsedAmount;
    final color = _colorForType(_type);
    final reasons = _reasons;
    final noteMissing =
        _submitted && _noteRequired && _note.text.trim().isEmpty;

    return AlertDialog(
      title: const Text('Registrar movimiento'),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  for (final type in const [
                    cashMovementDeposit,
                    cashMovementWithdrawal,
                    cashMovementExpense,
                  ])
                    Expanded(
                      child: Padding(
                        padding: EdgeInsets.only(
                          right: type == cashMovementExpense ? 0 : dpi.space(8),
                        ),
                        child: _TypePill(
                          label: _titleForType(type),
                          icon: _iconForType(type),
                          color: _colorForType(type),
                          selected: _type == type,
                          onTap: _submitting ? null : () => _selectType(type),
                        ),
                      ),
                    ),
                ],
              ),
              SizedBox(height: dpi.space(12)),
              Text(
                _explainerForType(_type),
                style: Theme.of(context).textTheme.bodySmall,
              ),
              SizedBox(height: dpi.space(14)),
              if (_sessions.length > 1) ...[
                _label(context, 'Caja'),
                Wrap(
                  spacing: dpi.space(8),
                  runSpacing: dpi.space(8),
                  children: [
                    for (final session in _sessions)
                      _ChoicePill(
                        label: session.registerName,
                        sublabel: session.openedByName,
                        selected: _session?.id == session.id,
                        onTap: _submitting
                            ? null
                            : () => setState(() => _session = session),
                      ),
                  ],
                ),
                if (_submitted && _session == null)
                  _fieldError(context, 'Elige la caja'),
                SizedBox(height: dpi.space(14)),
              ] else
                _singleSessionCard(context, _sessions.first),
              TextField(
                controller: _amount,
                autofocus: true,
                enabled: !_submitting,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: 'Monto',
                  prefixText: 'RD\$ ',
                  helperText: amount != null
                      ? 'Se registrará ${MangoFormatters.currency(amount)}'
                      : 'Miles con coma, centavos con punto',
                  errorText: _submitted && amount == null
                      ? 'Escribe un monto mayor que cero'
                      : null,
                ),
              ),
              SizedBox(height: dpi.space(14)),
              _label(context, 'Razón'),
              if (reasons.isEmpty)
                Text(
                  'Este negocio no tiene razones para ${cashMovementTypeLabel(_type)}s. '
                  'Agrégalas en el punto de venta.',
                  style: TextStyle(
                    fontSize: dpi.font(12),
                    color: MangoThemeFactory.warning,
                  ),
                )
              else
                Wrap(
                  spacing: dpi.space(8),
                  runSpacing: dpi.space(8),
                  children: [
                    for (final reason in reasons)
                      _ChoicePill(
                        label: reason.label,
                        selected: _reason?.code == reason.code,
                        onTap: _submitting
                            ? null
                            : () => setState(() => _reason = reason),
                      ),
                  ],
                ),
              if (_submitted && _reason == null && reasons.isNotEmpty)
                _fieldError(context, 'Elige una razón'),
              if (_reason?.requiresPin ?? false)
                Padding(
                  padding: EdgeInsets.only(top: dpi.space(6)),
                  child: Text(
                    'Esta razón exige aprobación de supervisor: se registrará '
                    'aprobada por ti.',
                    style: TextStyle(
                      fontSize: dpi.font(11),
                      color: MangoThemeFactory.warning,
                    ),
                  ),
                ),
              SizedBox(height: dpi.space(14)),
              TextField(
                controller: _note,
                enabled: !_submitting,
                onChanged: (_) => setState(() {}),
                maxLines: 2,
                decoration: InputDecoration(
                  labelText: _noteRequired ? 'Nota' : 'Nota (opcional)',
                  hintText: _hintForType(_type),
                  errorText: noteMissing ? 'Explica el motivo' : null,
                ),
              ),
              if (_error != null) ...[
                SizedBox(height: dpi.space(12)),
                Text(
                  _error!,
                  style: TextStyle(
                    fontSize: dpi.font(12),
                    color: MangoThemeFactory.danger,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _submitting ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _submitting || reasons.isEmpty ? null : _submit,
          style: FilledButton.styleFrom(
            backgroundColor: color,
            foregroundColor: Colors.white,
          ),
          child: Text(
            _submitting
                ? 'Guardando…'
                : 'Registrar ${cashMovementTypeLabel(_type)}',
          ),
        ),
      ],
    );
  }

  Widget _singleSessionCard(BuildContext context, RegisterSession session) {
    final dpi = DpiScale.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: dpi.space(14)),
      child: Container(
        padding: EdgeInsets.all(dpi.space(12)),
        decoration: BoxDecoration(
          color: MangoThemeFactory.altSurface(context),
          borderRadius: BorderRadius.circular(dpi.radius(14)),
          border: Border.all(color: MangoThemeFactory.borderColor(context)),
        ),
        child: Row(
          children: [
            Icon(
              Icons.point_of_sale_rounded,
              size: dpi.icon(18),
              color: MangoThemeFactory.success,
            ),
            SizedBox(width: dpi.space(10)),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    session.registerName,
                    style: TextStyle(
                      fontSize: dpi.font(13.5),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    'Abierta por ${session.openedByName}',
                    style: TextStyle(
                      fontSize: dpi.font(11),
                      color: MangoThemeFactory.mutedText(context),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _label(BuildContext context, String text) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(
      text.toUpperCase(),
      style: TextStyle(
        fontSize: DpiScale.of(context).font(11),
        fontWeight: FontWeight.w700,
        letterSpacing: 0.6,
        color: MangoThemeFactory.mutedText(context),
      ),
    ),
  );

  Widget _fieldError(BuildContext context, String text) => Padding(
    padding: const EdgeInsets.only(top: 6),
    child: Text(
      text,
      style: TextStyle(
        fontSize: DpiScale.of(context).font(11),
        color: MangoThemeFactory.danger,
      ),
    ),
  );

  String _titleForType(String type) {
    switch (type) {
      case cashMovementDeposit:
        return 'Ingreso';
      case cashMovementWithdrawal:
        return 'Retiro';
      default:
        return 'Gasto';
    }
  }

  /// Mismo código de color que el drill-down de la caja: verde entra, ámbar
  /// sale, rojo se gasta.
  Color _colorForType(String type) {
    switch (type) {
      case cashMovementDeposit:
        return MangoThemeFactory.success;
      case cashMovementWithdrawal:
        return MangoThemeFactory.warning;
      default:
        return MangoThemeFactory.danger;
    }
  }

  IconData _iconForType(String type) {
    switch (type) {
      case cashMovementDeposit:
        return Icons.south_west_rounded;
      case cashMovementWithdrawal:
        return Icons.north_east_rounded;
      default:
        return Icons.money_off_rounded;
    }
  }

  String _explainerForType(String type) {
    switch (type) {
      case cashMovementDeposit:
        return 'Entra efectivo a la caja y sube el efectivo esperado de su '
            'cierre. No es una venta: no lleva NCF.';
      case cashMovementWithdrawal:
        return 'Sale efectivo de la caja (bóveda, banco, entrega de turno) y '
            'baja el efectivo esperado de su cierre.';
      default:
        return 'Sale efectivo de la caja para pagar algo y baja el efectivo '
            'esperado de su cierre.';
    }
  }

  String _hintForType(String type) {
    switch (type) {
      case cashMovementDeposit:
        return 'Ej: fondo adicional, reposición de caja';
      case cashMovementWithdrawal:
        return 'Ej: retiro parcial, traslado a bóveda';
      default:
        return 'Ej: compra de hielo, limpieza, mensajería';
    }
  }
}

/// Selector de tipo: las tres opciones del POS (ingreso, retiro, gasto) con el
/// color de cada una, en la piel de card blanda del dashboard.
class _TypePill extends StatelessWidget {
  const _TypePill({
    required this.label,
    required this.icon,
    required this.color,
    required this.selected,
    this.onTap,
  });

  final String label;
  final IconData icon;
  final Color color;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final dpi = DpiScale.of(context);
    final radius = BorderRadius.circular(dpi.radius(12));
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: radius,
        child: Container(
          padding: EdgeInsets.symmetric(vertical: dpi.space(10)),
          decoration: BoxDecoration(
            color: selected
                ? color.withValues(alpha: 0.12)
                : MangoThemeFactory.altSurface(context),
            borderRadius: radius,
            border: Border.all(
              color: selected ? color : MangoThemeFactory.borderColor(context),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: dpi.icon(16),
                color: selected ? color : MangoThemeFactory.mutedText(context),
              ),
              SizedBox(height: dpi.space(4)),
              Text(
                label,
                style: TextStyle(
                  fontSize: dpi.font(12),
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: selected
                      ? color
                      : MangoThemeFactory.textColor(context),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Opción seleccionable con la misma piel de las cards blandas: sin sombra,
/// borde de 1px y mango cuando está elegida.
class _ChoicePill extends StatelessWidget {
  const _ChoicePill({
    required this.label,
    required this.selected,
    this.sublabel,
    this.onTap,
  });

  final String label;
  final String? sublabel;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final dpi = DpiScale.of(context);
    final radius = BorderRadius.circular(dpi.radius(12));
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: radius,
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: dpi.space(12),
            vertical: dpi.space(8),
          ),
          decoration: BoxDecoration(
            color: selected
                ? MangoThemeFactory.mango.withValues(alpha: 0.12)
                : MangoThemeFactory.altSurface(context),
            borderRadius: radius,
            border: Border.all(
              color: selected
                  ? MangoThemeFactory.mango
                  : MangoThemeFactory.borderColor(context),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: dpi.font(12.5),
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: selected
                      ? MangoThemeFactory.mangoDeep
                      : MangoThemeFactory.textColor(context),
                ),
              ),
              if (sublabel != null)
                Text(
                  sublabel!,
                  style: TextStyle(
                    fontSize: dpi.font(10.5),
                    color: MangoThemeFactory.mutedText(context),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
