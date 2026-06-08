import 'update_service_stub.dart'
    if (dart.library.js_interop) 'update_service_web.dart' as impl;

/// Lee el `build_id` publicado en `app_version.json` del servidor.
///
/// Devuelve `null` si no se puede obtener (archivo ausente, error de red,
/// o plataforma no web). En móvil siempre devuelve `null`.
Future<String?> fetchRemoteBuildId() => impl.fetchRemoteBuildId();

/// Recarga la aplicación para cargar la nueva versión. No-op fuera de la web.
void reloadApp() => impl.reloadApp();
