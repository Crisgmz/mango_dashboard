import 'package:shared_preferences/shared_preferences.dart';

/// Persiste y lee la **hora de corte del día operativo** por negocio.
///
/// "Hoy" en el dashboard arranca a esta hora del día actual y termina a esta
/// hora del día siguiente — así un turno que cruza medianoche (ej. 4 PM →
/// 2 AM) sigue contando como ventas de hoy.
///
/// Valores válidos: 0–23 (hora local). Default: 5 AM.
class BusinessDayService {
  static const int defaultCutoffHour = 5;
  static const int _minHour = 0;
  static const int _maxHour = 23;

  String _key(String businessId) => 'business_day_cutoff_$businessId';

  Future<int> loadCutoffHour(String businessId) async {
    if (businessId.isEmpty) return defaultCutoffHour;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getInt(_key(businessId));
    if (raw == null) return defaultCutoffHour;
    if (raw < _minHour || raw > _maxHour) return defaultCutoffHour;
    return raw;
  }

  Future<void> saveCutoffHour(String businessId, int hour) async {
    if (businessId.isEmpty) return;
    final clamped = hour.clamp(_minHour, _maxHour);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_key(businessId), clamped);
  }
}
