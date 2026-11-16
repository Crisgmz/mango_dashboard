import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Nota de venta del negocio: documento SIN valor fiscal (NV-000123) que el
/// cajero puede elegir en el cobro de consumidor final pagado en efectivo.
///
/// Se enciende SOLO desde el dashboard (16-nov-2026): la POS lo lee de
/// `business_settings` pero ya no lo muestra ni lo guarda. Ahí el cobro
/// siempre arranca con factura; la nota la elige el cajero, sin cupo.
@immutable
class SalesNoteSettings {
  const SalesNoteSettings({required this.enabled, required this.prefix});

  final bool enabled;
  final String prefix;

  static const defaultPrefix = 'NV-';

  /// Mismo tope que tenía el campo en la POS.
  static const maxPrefixLength = 6;

  static const disabled = SalesNoteSettings(enabled: false, prefix: defaultPrefix);

  /// Mayúsculas, sin espacios, a lo sumo [maxPrefixLength]. Vacío vuelve a
  /// [defaultPrefix]: sin prefijo la nota se imprimiría como un número
  /// pelado, igual a un número de orden.
  static String normalizePrefix(String? raw) {
    final clean = (raw ?? '').replaceAll(RegExp(r'\s+'), '').toUpperCase();
    if (clean.isEmpty) return defaultPrefix;
    return clean.length > maxPrefixLength ? clean.substring(0, maxPrefixLength) : clean;
  }

  factory SalesNoteSettings.fromRow(Map<String, dynamic>? row) => SalesNoteSettings(
        enabled: row?['sales_note_enabled'] == true,
        prefix: normalizePrefix(row?['sales_note_prefix']?.toString()),
      );

  SalesNoteSettings copyWith({bool? enabled, String? prefix}) =>
      SalesNoteSettings(enabled: enabled ?? this.enabled, prefix: prefix ?? this.prefix);
}

class SalesNoteSettingsService {
  SalesNoteSettingsService(this._client);

  final SupabaseClient _client;

  Future<SalesNoteSettings> load(String businessId) async {
    final row = await _client
        .from('business_settings')
        .select('sales_note_enabled, sales_note_prefix')
        .eq('business_id', businessId)
        .maybeSingle();
    return SalesNoteSettings.fromRow(row);
  }

  /// Guarda solo las columnas de la nota de venta (upsert por negocio: el
  /// resto de los ajustes de la POS no se toca). Solo dueño/admin pasan RLS.
  Future<void> save(String businessId, SalesNoteSettings settings) async {
    await _client.from('business_settings').upsert(
      saveRow(businessId, settings),
      onConflict: 'business_id',
    );
  }

  @visibleForTesting
  static Map<String, dynamic> saveRow(String businessId, SalesNoteSettings settings) => {
        'business_id': businessId,
        'sales_note_enabled': settings.enabled,
        'sales_note_prefix': SalesNoteSettings.normalizePrefix(settings.prefix),
      };
}
