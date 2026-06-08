import 'dart:convert';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

/// Descarga `version.json` con cache-busting y devuelve su campo `build_id`.
Future<String?> fetchRemoteBuildId() async {
  try {
    // El query param evita que el navegador sirva una copia cacheada.
    final url = 'app_version.json?t=${DateTime.now().millisecondsSinceEpoch}';
    final response = await web.window
        .fetch(url.toJS, web.RequestInit(cache: 'no-store'))
        .toDart;
    if (!response.ok) return null;
    final body = (await response.text().toDart).toDart;
    final data = jsonDecode(body) as Map<String, dynamic>;
    final buildId = data['build_id'];
    return buildId?.toString();
  } catch (_) {
    return null;
  }
}

void reloadApp() {
  web.window.location.reload();
}
