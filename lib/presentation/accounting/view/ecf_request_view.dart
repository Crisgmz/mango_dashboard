import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/formatters/mango_formatters.dart';
import '../../../core/responsive/dpi_scale.dart';
import '../../../domain/accounting/ecf_request.dart';
import '../../auth/viewmodel/auth_gate_view_model.dart';
import '../../theme/theme_data_factory.dart';
import '../viewmodel/ecf_request_view_model.dart';
import 'ecf_request_form_view.dart';

/// Facturación electrónica (e-CF): pedirla y seguir en qué paso va.
///
/// El avance lo calcula el servidor a partir de lo que ya existe —el alta con
/// el proveedor, la autorización de la DGII, las secuencias e-NCF y el
/// aprovisionamiento—, así que acá no hay estado propio: se consulta y se
/// pinta. Misma Edge Function que usa la POS.
class EcfRequestView extends ConsumerWidget {
  const EcfRequestView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dpi = DpiScale.of(context);
    final statusAsync = ref.watch(ecfRequestStatusProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Facturación electrónica'),
        centerTitle: false,
        actions: [
          IconButton(
            tooltip: 'Actualizar',
            onPressed: () => ref.invalidate(ecfRequestStatusProvider),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: statusAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => _ErrorBody(
          message: e is EcfRequestException
              ? e.message
              : 'No se pudo consultar el estado de la facturación electrónica.',
          onRetry: () => ref.invalidate(ecfRequestStatusProvider),
        ),
        data: (status) => ListView(
          physics: const AlwaysScrollableScrollPhysics(
              parent: BouncingScrollPhysics()),
          padding: EdgeInsets.fromLTRB(dpi.space(16), dpi.space(16),
              dpi.space(16), dpi.space(24) + MediaQuery.of(context).padding.bottom),
          children: [
            _StatusCard(status: status),
            SizedBox(height: dpi.space(12)),
            _NextStepCard(status: status),
            if (status.stage != EcfRequestStage.active) ...[
              SizedBox(height: dpi.space(12)),
              const _WhatYouNeedCard(),
            ],
          ],
        ),
      ),
    );
  }
}

/// Los cinco pasos del alta, en el orden en que ocurren. El índice coincide con
/// [EcfRequestStage.stepIndex]: la etapa dice en cuál está parado.
const _steps = <({String title, String detail})>[
  (
    title: 'Solicitud enviada',
    detail: 'Recibimos tus datos y tu certificado de firma digital.'
  ),
  (
    title: 'Empresa registrada con el proveedor',
    detail: 'Tu RNC queda dado de alta con el proveedor de e-CF.'
  ),
  (
    title: 'Autorización de la DGII',
    detail: 'Postulación y set de pruebas en tu Oficina Virtual.'
  ),
  (
    title: 'Secuencias e-NCF cargadas',
    detail: 'Las series E31, E32 y E34 autorizadas para tu RNC.'
  ),
  (
    title: 'Activación',
    detail: 'MangoPOS enciende la emisión electrónica en tu caja.'
  ),
];

class _StatusCard extends ConsumerWidget {
  const _StatusCard({required this.status});

  final EcfRequestStatus status;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dpi = DpiScale.of(context);
    final isActive = status.stage == EcfRequestStage.active;
    final accent =
        isActive ? MangoThemeFactory.success : MangoThemeFactory.mango;

    return Container(
      padding: EdgeInsets.all(dpi.space(16)),
      decoration: BoxDecoration(
        color: MangoThemeFactory.cardColor(context),
        borderRadius: BorderRadius.circular(dpi.radius(16)),
        border: Border.all(color: MangoThemeFactory.borderColor(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: dpi.scale(44),
                height: dpi.scale(44),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(dpi.radius(12)),
                ),
                child: Icon(
                  isActive
                      ? Icons.verified_rounded
                      : Icons.verified_outlined,
                  color: accent,
                  size: dpi.icon(22),
                ),
              ),
              SizedBox(width: dpi.space(14)),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      switch (status.stage) {
                        EcfRequestStage.none => 'Conviértete en emisor electrónico',
                        EcfRequestStage.active => 'Facturación electrónica activa',
                        _ => 'Solicitud en curso',
                      },
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    SizedBox(height: dpi.space(2)),
                    Text(
                      status.stage == EcfRequestStage.none
                          ? 'MangoPOS registra tu empresa con su proveedor y te '
                              'acompaña en la certificación ante la DGII.'
                          : status.requestedAt != null
                              ? 'Enviada el ${MangoFormatters.date(status.requestedAt!)}'
                              : 'La inició MangoPOS desde su panel.',
                      style: TextStyle(
                        fontSize: dpi.font(12),
                        color: MangoThemeFactory.mutedText(context),
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (status.stage == EcfRequestStage.none) ...[
            SizedBox(height: dpi.space(14)),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => _request(context, ref, status),
                child: const Text('Solicitar facturación electrónica'),
              ),
            ),
          ] else if (status.stage != EcfRequestStage.active) ...[
            SizedBox(height: dpi.space(16)),
            for (var i = 0; i < _steps.length; i++)
              _Step(
                title: _steps[i].title,
                detail: _steps[i].detail,
                done: i < status.stage.stepIndex,
                current: i == status.stage.stepIndex,
                isLast: i == _steps.length - 1,
              ),
            // El alta con el proveedor puede haber fallado por una contraseña
            // equivocada: en ese caso el cliente reenvía con el certificado
            // correcto sin esperar a nadie.
            if (status.stage == EcfRequestStage.company) ...[
              SizedBox(height: dpi.space(12)),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () => _request(context, ref, status),
                  child: const Text('Enviar de nuevo con mi certificado'),
                ),
              ),
            ],
          ],
          if (status.contactName != null &&
              status.stage != EcfRequestStage.active) ...[
            SizedBox(height: dpi.space(12)),
            Text(
              'Contacto: ${status.contactName}'
              '${status.contactPhone != null ? ' · ${status.contactPhone}' : ''}',
              style: TextStyle(
                fontSize: dpi.font(11.5),
                color: MangoThemeFactory.mutedText(context),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _request(
    BuildContext context,
    WidgetRef ref,
    EcfRequestStatus status,
  ) async {
    final businessId = ref.read(authGateViewModelProvider).profile?.businessId;
    if (businessId == null) return;
    final messenger = ScaffoldMessenger.of(context);
    final result = await openEcfRequestForm(
      context,
      businessId: businessId,
      status: status,
    );
    if (result == null) return;
    ref.invalidate(ecfRequestStatusProvider);
    messenger.showSnackBar(SnackBar(
      content: Text(result.companyRegistered
          ? 'Solicitud enviada. MangoPOS te contactará para seguir.'
          : result.message ?? 'Solicitud enviada. MangoPOS te contactará.'),
    ));
  }
}

class _NextStepCard extends StatelessWidget {
  const _NextStepCard({required this.status});

  final EcfRequestStatus status;

  @override
  Widget build(BuildContext context) {
    final dpi = DpiScale.of(context);
    final text = _nextStepText(status);
    if (text.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: EdgeInsets.all(dpi.space(14)),
      decoration: BoxDecoration(
        color: MangoThemeFactory.altSurface(context),
        borderRadius: BorderRadius.circular(dpi.radius(14)),
        border: Border.all(color: MangoThemeFactory.borderColor(context)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.flag_rounded,
              size: dpi.icon(18), color: MangoThemeFactory.mango),
          SizedBox(width: dpi.space(10)),
          Expanded(
            child: Text(
              text,
              style: TextStyle(fontSize: dpi.font(12.5), height: 1.4),
            ),
          ),
        ],
      ),
    );
  }

  String _nextStepText(EcfRequestStatus status) {
    switch (status.stage) {
      case EcfRequestStage.none:
        return 'Necesitas tu certificado de firma digital (.p12) y los datos de '
            'tu empresa tal como están en la DGII.';
      case EcfRequestStage.company:
        return 'Recibimos tu solicitud, pero tu empresa todavía no quedó '
            'registrada con el proveedor. Si tu certificado o la contraseña '
            'dieron error, vuelve a enviarla. MangoPOS te contactará.';
      case EcfRequestStage.certification:
        return status.alreadyAuthorized == true
            ? 'Tu empresa ya está registrada. Indicaste que ya eres emisor '
                'electrónico: MangoPOS lo confirma con la DGII y sigue con tus '
                'secuencias.'
            : 'Tu empresa ya está registrada. Sigue la certificación ante la '
                'DGII: MangoPOS te guía con la postulación y las pruebas en tu '
                'Oficina Virtual.';
      case EcfRequestStage.sequences:
        return 'La DGII ya te autorizó. Solicita en tu Oficina Virtual las '
            'secuencias E31, E32 y E34, y envíale a MangoPOS el PDF de la '
            'autorización.';
      case EcfRequestStage.activation:
        return 'Todo está listo: MangoPOS está activando tu facturación '
            'electrónica.';
      case EcfRequestStage.active:
        return 'Tu negocio emite comprobantes electrónicos (serie E). Cada '
            'factura electrónica queda en el historial de ventas de la POS, y '
            'los e-CF aceptados entran en el 607 como cualquier otro '
            'comprobante.';
    }
  }
}

class _WhatYouNeedCard extends StatelessWidget {
  const _WhatYouNeedCard();

  @override
  Widget build(BuildContext context) {
    final dpi = DpiScale.of(context);
    const items = [
      'Certificado de firma digital (.p12) a nombre de la empresa o de su '
          'representante legal, con su contraseña.',
      'RNC, razón social y dirección fiscal exactamente como están en la DGII '
          '(la fiscal puede no ser la del local).',
      'Una persona de contacto con teléfono, para coordinar la certificación.',
    ];
    return Container(
      padding: EdgeInsets.all(dpi.space(14)),
      decoration: BoxDecoration(
        color: MangoThemeFactory.cardColor(context),
        borderRadius: BorderRadius.circular(dpi.radius(14)),
        border: Border.all(color: MangoThemeFactory.borderColor(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'QUÉ NECESITAS',
            style: TextStyle(
              fontSize: dpi.font(11),
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
              color: MangoThemeFactory.mutedText(context),
            ),
          ),
          SizedBox(height: dpi.space(10)),
          for (final item in items)
            Padding(
              padding: EdgeInsets.only(bottom: dpi.space(8)),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.circle,
                      size: dpi.icon(5),
                      color: MangoThemeFactory.mutedText(context)),
                  SizedBox(width: dpi.space(10)),
                  Expanded(
                    child: Text(
                      item,
                      style: TextStyle(fontSize: dpi.font(12.5), height: 1.4),
                    ),
                  ),
                ],
              ),
            ),
          Text(
            'MangoPOS no guarda el certificado ni su contraseña: viajan al '
            'proveedor de facturación electrónica en la misma petición.',
            style: TextStyle(
              fontSize: dpi.font(11.5),
              color: MangoThemeFactory.mutedText(context),
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({
    required this.title,
    required this.detail,
    required this.done,
    required this.current,
    required this.isLast,
  });

  final String title;
  final String detail;
  final bool done;
  final bool current;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final dpi = DpiScale.of(context);
    final muted = MangoThemeFactory.mutedText(context);
    final color = done
        ? MangoThemeFactory.success
        : current
            ? MangoThemeFactory.mango
            : muted;
    return Padding(
      padding: EdgeInsets.only(bottom: isLast ? 0 : dpi.space(10)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            done
                ? Icons.check_circle_rounded
                : current
                    ? Icons.radio_button_checked_rounded
                    : Icons.radio_button_unchecked_rounded,
            size: dpi.icon(18),
            color: color,
          ),
          SizedBox(width: dpi.space(10)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: dpi.font(13),
                    fontWeight: done || current ? FontWeight.w700 : FontWeight.w400,
                    color: done || current ? null : muted,
                  ),
                ),
                if (current) ...[
                  SizedBox(height: dpi.space(2)),
                  Text(
                    detail,
                    style: TextStyle(fontSize: dpi.font(11.5), color: muted),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorBody extends StatelessWidget {
  const _ErrorBody({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final dpi = DpiScale.of(context);
    return Center(
      child: Padding(
        padding: EdgeInsets.all(dpi.space(28)),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.cloud_off_rounded,
                size: dpi.icon(42), color: MangoThemeFactory.mutedText(context)),
            SizedBox(height: dpi.space(12)),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: dpi.font(13), height: 1.4),
            ),
            SizedBox(height: dpi.space(14)),
            OutlinedButton(onPressed: onRetry, child: const Text('Reintentar')),
          ],
        ),
      ),
    );
  }
}
