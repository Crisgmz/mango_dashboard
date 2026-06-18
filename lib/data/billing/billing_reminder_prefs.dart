import 'package:shared_preferences/shared_preferences.dart';

/// Recuerda si el popup de recordatorio de cobro ya se mostró hoy, por negocio,
/// para no repetirlo en cada apertura del app.
class BillingReminderPrefs {
  String _key(String businessId) => 'billing_reminder_popup_$businessId';

  /// Día actual local en formato `yyyy-MM-dd`.
  String _today() {
    final now = DateTime.now();
    return '${now.year.toString().padLeft(4, '0')}-'
        '${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';
  }

  Future<bool> wasShownToday(String businessId) async {
    if (businessId.isEmpty) return true;
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_key(businessId)) == _today();
  }

  Future<void> markShownToday(String businessId) async {
    if (businessId.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key(businessId), _today());
  }
}
