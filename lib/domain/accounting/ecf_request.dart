import 'dart:typed_data';

import 'package:flutter/foundation.dart' show immutable;

/// Solicitud de facturación electrónica (e-CF) que hace el dueño del negocio.
///
/// Espejo de `lib/data/repositories/ecf_request_repository.dart` en la POS: los
/// dos hablan con la misma Edge Function `ecf-onboarding` (acciones
/// `request_status` y `submit_request`), que solo acepta al dueño o
/// administrador del negocio. El certificado viaja a Alanube en la misma
/// petición y no se guarda en MangoPOS.

/// En qué va la facturación electrónica del negocio (lo deriva el servidor a
/// partir del alta con el proveedor, la autorización de la DGII, las
/// secuencias e-NCF y el aprovisionamiento).
enum EcfRequestStage {
  /// Nunca la pidió.
  none,

  /// Pedida; falta registrar la empresa con el proveedor.
  company,

  /// Falta la autorización de la DGII.
  certification,

  /// Autorizado; faltan las secuencias e-NCF.
  sequences,

  /// Todo listo; falta activarla.
  activation,

  /// Ya emite comprobantes electrónicos.
  active;

  static EcfRequestStage parse(String? raw) =>
      EcfRequestStage.values.firstWhere(
        (s) => s.name == raw,
        orElse: () => EcfRequestStage.none,
      );

  /// Posición en la fila de pasos (0 = solicitud enviada). `none` no cuenta:
  /// todavía no hay solicitud que mostrar.
  int get stepIndex => index - 1;
}

@immutable
class EcfRequestStatus {
  const EcfRequestStatus({
    required this.stage,
    this.requestedAt,
    this.contactName,
    this.contactPhone,
    this.alreadyAuthorized,
    this.data = const EcfRequestData(),
  });

  final EcfRequestStage stage;
  final DateTime? requestedAt;
  final String? contactName;
  final String? contactPhone;

  /// Lo que el cliente declaró al pedirla: si ya es emisor electrónico
  /// autorizado por la DGII. Informativo — lo confirma el operador.
  final bool? alreadyAuthorized;

  /// Lo último que mandó (o lo que el negocio ya tenía en `fiscal_settings`):
  /// precarga el formulario.
  final EcfRequestData data;

  factory EcfRequestStatus.fromJson(Map<String, dynamic> json) {
    final data = json['data'];
    return EcfRequestStatus(
      stage: EcfRequestStage.parse(json['stage'] as String?),
      requestedAt: DateTime.tryParse(json['requested_at']?.toString() ?? ''),
      contactName: json['contact_name'] as String?,
      contactPhone: json['contact_phone'] as String?,
      alreadyAuthorized: json['already_authorized'] as bool?,
      data: data is Map
          ? EcfRequestData.fromJson(Map<String, dynamic>.from(data))
          : const EcfRequestData(),
    );
  }
}

/// Datos del contribuyente tal como están en la DGII. La dirección FISCAL
/// puede no ser la del local que sale en el ticket.
@immutable
class EcfRequestData {
  const EcfRequestData({
    this.rnc,
    this.legalName,
    this.tradeName,
    this.fiscalAddress,
    this.province,
    this.municipality,
    this.email,
  });

  final String? rnc;
  final String? legalName;
  final String? tradeName;
  final String? fiscalAddress;
  final String? province;
  final String? municipality;
  final String? email;

  factory EcfRequestData.fromJson(Map<String, dynamic> json) => EcfRequestData(
        rnc: json['rnc'] as String?,
        legalName: json['legal_name'] as String?,
        tradeName: json['trade_name'] as String?,
        fiscalAddress: json['fiscal_address'] as String?,
        province: json['province'] as String?,
        municipality: json['municipality'] as String?,
        email: json['email'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'rnc': rnc,
        'legal_name': legalName,
        'trade_name': tradeName,
        'fiscal_address': fiscalAddress,
        'province': province,
        'municipality': municipality,
        'email': email,
      };
}

@immutable
class EcfRequestSubmission {
  const EcfRequestSubmission({
    required this.data,
    required this.contactName,
    required this.contactPhone,
    required this.alreadyAuthorized,
    required this.certificateFilename,
    required this.certificateBytes,
    required this.certificatePassword,
  });

  final EcfRequestData data;
  final String contactName;
  final String contactPhone;
  final bool alreadyAuthorized;
  final String certificateFilename;
  final Uint8List certificateBytes;
  final String certificatePassword;
}

@immutable
class EcfRequestResult {
  const EcfRequestResult({required this.companyRegistered, this.message});

  /// La empresa quedó registrada con el proveedor en este envío.
  final bool companyRegistered;

  /// Aviso del servidor cuando no se registró (por ejemplo, ya existía).
  final String? message;
}

class EcfRequestException implements Exception {
  const EcfRequestException(this.message, {this.code});

  final String message;
  final String? code;

  @override
  String toString() => message;
}
