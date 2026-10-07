import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/di/providers.dart';
import '../../../domain/accounting/ecf_request.dart';
import '../../auth/viewmodel/auth_gate_view_model.dart';

/// Estado de la solicitud de facturación electrónica del negocio activo. Lo
/// deriva el servidor en cada consulta, así que acá no se cachea nada: se
/// invalida y se vuelve a preguntar.
final ecfRequestStatusProvider =
    FutureProvider.autoDispose<EcfRequestStatus>((ref) async {
  final businessId = ref.watch(authGateViewModelProvider).profile?.businessId;
  if (businessId == null) {
    throw const EcfRequestException('No hay un negocio activo.');
  }
  return ref.read(ecfRequestServiceProvider).status(businessId);
});
