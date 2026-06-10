/// Parser for the cashier-reported breakdown embedded in
/// `cash_register_sessions.notes`. Mirrors the POS app so the dashboard shows
/// the same reported values. Supports both note formats:
///
/// Blind close (compact):
///   `Cierre ciego | Efectivo: {x} | Tarjetas: {y} | Transferencias: {z} |
///    Total reportado: {t} | Dif. efectivo: {a} | ... [| Cierre forzado con N mesa(s) abiertas]`
///
/// Detailed close (wizard):
///   `Cierre detallado | Efectivo: {x} | Tarjeta: {y} | Transferencia: {z} | Total reportado: {t}`
///
/// Traps handled:
///  - Plural (`Tarjetas`/`Transferencias`) vs singular (`Tarjeta`/`Transferencia`).
///  - `Dif. *` fields are ignored — they can be garbage on old sessions; the
///    dashboard always recomputes differences from expected vs reported.
library;

class CashCloseReported {
  const CashCloseReported({
    this.cash,
    this.card,
    this.transfer,
    this.total,
    this.mode,
    this.forcedCloseNote,
  });

  final double? cash;
  final double? card;
  final double? transfer;

  /// Explicit "Total reportado" from notes. Null when absent.
  final double? total;

  /// `blind | detailed | null`.
  final String? mode;

  /// Full "Cierre forzado con N mesa(s) abiertas" segment, if present.
  final String? forcedCloseNote;

  static const empty = CashCloseReported();
}

CashCloseReported parseCashCloseNotes(String? notes) {
  if (notes == null || notes.trim().isEmpty) return CashCloseReported.empty;

  double? cash;
  double? card;
  double? transfer;
  double? total;
  String? mode;
  String? forcedCloseNote;

  for (final segment in notes.split('|')) {
    final trimmed = segment.trim();
    if (trimmed.isEmpty) continue;
    final lower = _stripAccents(trimmed.toLowerCase());

    if (lower.startsWith('cierre ciego')) {
      mode = 'blind';
      continue;
    }
    if (lower.startsWith('cierre detallado')) {
      mode = 'detailed';
      continue;
    }
    if (lower.startsWith('cierre forzado')) {
      forcedCloseNote = trimmed;
      continue;
    }

    final colon = trimmed.indexOf(':');
    if (colon < 0) continue;
    final key = _stripAccents(trimmed.substring(0, colon).trim().toLowerCase());
    final value = trimmed.substring(colon + 1);

    // Never trust the "Dif. *" fields from notes.
    if (key.startsWith('dif')) continue;

    if (key.startsWith('efectivo')) {
      cash = _parseNum(value);
    } else if (key.startsWith('tarjeta')) {
      card = _parseNum(value);
    } else if (key.startsWith('transferencia')) {
      transfer = _parseNum(value);
    } else if (key.startsWith('total reportado') || key == 'total') {
      total = _parseNum(value);
    }
  }

  return CashCloseReported(
    cash: cash,
    card: card,
    transfer: transfer,
    total: total,
    mode: mode,
    forcedCloseNote: forcedCloseNote,
  );
}

/// Parses a number that may carry a currency symbol and en_US thousands
/// separators (e.g. `RD$ 24,310.00` → 24310.0, `-2,550` → -2550.0).
double? _parseNum(String raw) {
  final cleaned = raw.replaceAll(RegExp(r'[^0-9.,-]'), '');
  if (cleaned.isEmpty) return null;
  // App formats with NumberFormat en_US: ',' = thousands, '.' = decimal.
  final normalized = cleaned.replaceAll(',', '');
  return double.tryParse(normalized);
}

String _stripAccents(String input) {
  const from = 'áéíóúüñ';
  const to = 'aeiouun';
  var out = input;
  for (var i = 0; i < from.length; i++) {
    out = out.replaceAll(from[i], to[i]);
  }
  return out;
}
