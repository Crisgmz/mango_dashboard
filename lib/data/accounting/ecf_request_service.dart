import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/accounting/ecf_request.dart';

/// Habla con la Edge Function `ecf-onboarding` del backend compartido con la
/// POS. Solo usa las dos acciones de cliente (`request_status`,
/// `submit_request`); todo lo demás de esa función es para operadores de
/// MangoPOS y el servidor lo rechaza desde acá.
///
/// El servidor valida que el usuario sea dueño o administrador del negocio, así
/// que no hay chequeo de rol duplicado en el cliente. El certificado va en la
/// misma petición y no se guarda: ni en el dashboard ni en MangoPOS.
class EcfRequestService {
  EcfRequestService(this._client);

  final SupabaseClient _client;

  Future<EcfRequestStatus> status(String businessId) async {
    final data = await _invoke({
      'action': 'request_status',
      'business_id': businessId,
    });
    return EcfRequestStatus.fromJson(data);
  }

  Future<EcfRequestResult> submit(
    String businessId,
    EcfRequestSubmission submission,
  ) async {
    final data = await _invoke({
      'action': 'submit_request',
      'business_id': businessId,
      'data': submission.data.toJson(),
      'contact_name': submission.contactName,
      'contact_phone': submission.contactPhone,
      'already_authorized': submission.alreadyAuthorized,
      'accept_terms': true,
      'certificate': {
        'filename': submission.certificateFilename,
        'content_base64': base64Encode(submission.certificateBytes),
        'password': submission.certificatePassword,
      },
    });
    return EcfRequestResult(
      companyRegistered: data['company_registered'] == true,
      message: data['message'] as String?,
    );
  }

  Future<Map<String, dynamic>> _invoke(Map<String, dynamic> body) async {
    try {
      final res = await _client.functions.invoke('ecf-onboarding', body: body);
      final data = res.data;
      if (data is Map) return Map<String, dynamic>.from(data);
      throw const EcfRequestException('Respuesta inesperada del servidor.');
    } on FunctionException catch (e) {
      // La función devuelve { error: { code, message } } en los fallos
      // esperados (datos incompletos, certificado inválido, sin permiso).
      final details = e.details;
      if (details is Map && details['error'] is Map) {
        final err = Map<String, dynamic>.from(details['error'] as Map);
        throw EcfRequestException(
          (err['message'] as String?) ?? 'No se pudo completar la solicitud.',
          code: err['code'] as String?,
        );
      }
      throw EcfRequestException(
        e.status == 404
            ? 'El servidor todavía no tiene esta función disponible.'
            : 'No se pudo completar la solicitud. Intenta de nuevo.',
      );
    }
  }
}
