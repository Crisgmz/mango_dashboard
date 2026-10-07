import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/accounting/dgii_reports.dart';

/// Recuerda las dos columnas de criterio contable que el sistema no registra:
/// el tipo de bien/servicio de cada proveedor (606, col. 3) y el tipo de
/// anulación de cada comprobante (608, col. 3).
///
/// Vive en las preferencias del dispositivo, no en el backend: son decisiones
/// del contador sobre cómo declarar, no datos de la operación, y ninguna tabla
/// del POS tiene columna para ellas. La consecuencia a tener presente es que la
/// clasificación no viaja entre dispositivos — al abrir el dashboard en otro
/// equipo hay que volver a marcar lo que se salga del default.
class DgiiClassificationStore {
  static const _expensePrefix = 'dgii_606_expense_type_';
  static const _voidPrefix = 'dgii_608_void_reason_';

  Future<DgiiClassification> load(String businessId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return DgiiClassification(
        expenseTypeBySupplier: _decode(prefs.getString('$_expensePrefix$businessId')),
        voidReasonByNcf: _decode(prefs.getString('$_voidPrefix$businessId')),
      );
    } catch (_) {
      // Sin preferencias disponibles los formatos siguen saliendo con los
      // defaults; no vale la pena tumbar la pantalla por esto.
      return const DgiiClassification();
    }
  }

  Future<void> save(String businessId, DgiiClassification value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
          '$_expensePrefix$businessId', jsonEncode(value.expenseTypeBySupplier));
      await prefs.setString(
          '$_voidPrefix$businessId', jsonEncode(value.voidReasonByNcf));
    } catch (_) {
      // Guardar es una comodidad, no un requisito: el archivo ya se exportó
      // con lo que el usuario eligió en pantalla.
    }
  }

  Map<String, String> _decode(String? raw) {
    if (raw == null || raw.isEmpty) return const {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return const {};
      return {
        for (final entry in decoded.entries)
          entry.key.toString(): entry.value.toString(),
      };
    } catch (_) {
      return const {};
    }
  }
}
