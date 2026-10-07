/// Catálogos de códigos de la DGII usados por los formatos 606, 607 y 608
/// (Norma General 06-2018). Son los valores que el prevalidador acepta en las
/// columnas de clasificación; van como texto de dos dígitos en el TXT.
///
/// Cada catálogo es `(code, label)` para poder pintarlo en un selector sin
/// duplicar los textos en la vista.
library;

import 'package:flutter/foundation.dart' show immutable;

@immutable
class DgiiCode {
  const DgiiCode(this.code, this.label);

  /// Valor que va en el archivo (`'01'`, `'09'`, …).
  final String code;

  /// Texto que lee el usuario.
  final String label;

  /// `01 · Gastos de personal` — para selectores y listas.
  String get display => '$code · $label';

  @override
  bool operator ==(Object other) => other is DgiiCode && other.code == code;

  @override
  int get hashCode => code.hashCode;
}

/// Busca un código en un catálogo; devuelve null si no está.
DgiiCode? dgiiCodeOf(List<DgiiCode> catalog, String? code) {
  if (code == null || code.isEmpty) return null;
  for (final c in catalog) {
    if (c.code == code) return c;
  }
  return null;
}

// ── Tipo de identificación (606 col. 2 · 607 col. 2) ────────────────────────

/// 1 = RNC (9 dígitos), 2 = Cédula (11 dígitos), 3 = Pasaporte.
const kDgiiIdTypes = <DgiiCode>[
  DgiiCode('1', 'RNC'),
  DgiiCode('2', 'Cédula'),
  DgiiCode('3', 'Pasaporte'),
];

/// Deduce el tipo de identificación por la forma del número, que es lo único
/// que garantiza la DGII: 9 dígitos = RNC, 11 = cédula, cualquier otra cosa
/// con letras = pasaporte. Devuelve null cuando no hay número (consumidor
/// final sin identificar): esa columna va vacía en el 607.
String? dgiiIdTypeFor(String? taxId, {String? declaredType}) {
  final digits = (taxId ?? '').replaceAll(RegExp(r'\D'), '');
  if (digits.isEmpty) {
    // Sin dígitos: solo es pasaporte si de verdad escribieron algo.
    final raw = (taxId ?? '').trim();
    return raw.isEmpty ? null : '3';
  }
  // Lo declarado en `suppliers.tax_id_type` manda cuando es coherente.
  switch (declaredType) {
    case 'rnc':
      return '1';
    case 'cedula':
      return '2';
    case 'pasaporte':
      return '3';
  }
  if (digits.length == 11) return '2';
  if (digits.length == 9) return '1';
  return '3';
}

// ── Tipo de bienes y servicios comprados (606 col. 3) ───────────────────────

const kDgiiExpenseTypes = <DgiiCode>[
  DgiiCode('01', 'Gastos de personal'),
  DgiiCode('02', 'Gastos por trabajos, suministros y servicios'),
  DgiiCode('03', 'Arrendamientos'),
  DgiiCode('04', 'Gastos de activos fijos'),
  DgiiCode('05', 'Gastos de representación'),
  DgiiCode('06', 'Otras deducciones admitidas'),
  DgiiCode('07', 'Gastos financieros'),
  DgiiCode('08', 'Gastos extraordinarios'),
  DgiiCode('09', 'Compras y gastos que forman parte del costo de venta'),
  DgiiCode('10', 'Adquisiciones de activos'),
  DgiiCode('11', 'Gastos de seguros'),
];

/// Por defecto 09: en un restaurante la inmensa mayoría de las recepciones con
/// NCF son insumos que entran al costo de venta. El usuario lo cambia por
/// proveedor cuando no aplica (alquiler → 03, seguros → 11, …).
const kDgiiDefaultExpenseType = '09';

// ── Forma de pago (606 col. 23) ─────────────────────────────────────────────

const kDgiiPurchasePaymentForms = <DgiiCode>[
  DgiiCode('01', 'Efectivo'),
  DgiiCode('02', 'Cheque / Transferencia / Depósito'),
  DgiiCode('03', 'Tarjeta de crédito o débito'),
  DgiiCode('04', 'Compra a crédito'),
  DgiiCode('05', 'Permuta'),
  DgiiCode('06', 'Nota de crédito'),
  DgiiCode('07', 'Mixto'),
];

/// Traduce el `payment_method` que guardó la recepción al código del 606.
/// Lo que no reconoce cae en efectivo, que es el default de una compra de
/// mostrador y lo que el prevalidador espera cuando no se declara nada.
String dgiiPurchasePaymentForm(String? raw) {
  switch ((raw ?? '').trim().toLowerCase()) {
    case 'cash':
    case 'efectivo':
      return '01';
    case 'transfer':
    case 'transferencia':
    case 'cheque':
    case 'check':
    case 'deposit':
    case 'deposito':
    case 'depósito':
      return '02';
    case 'card':
    case 'tarjeta':
      return '03';
    case 'credit':
    case 'credito':
    case 'crédito':
      return '04';
    case 'permuta':
      return '05';
    case 'nota_credito':
    case 'credit_note':
      return '06';
    case 'mixed':
    case 'mixto':
      return '07';
    default:
      return '01';
  }
}

// ── Tipo de retención en ISR (606 col. 17) ──────────────────────────────────

const kDgiiIsrWithholdingTypes = <DgiiCode>[
  DgiiCode('01', 'Alquileres'),
  DgiiCode('02', 'Honorarios por servicios'),
  DgiiCode('03', 'Otras rentas'),
  DgiiCode('04', 'Otras rentas (rentas presuntas)'),
  DgiiCode('05', 'Intereses a personas jurídicas residentes'),
  DgiiCode('06', 'Intereses a personas físicas residentes'),
  DgiiCode('07', 'Retención por proveedores del Estado'),
  DgiiCode('08', 'Juegos telefónicos'),
];

// ── Tipo de ingreso (607 col. 5) ────────────────────────────────────────────

const kDgiiIncomeTypes = <DgiiCode>[
  DgiiCode('01', 'Ingresos por operaciones (no financieros)'),
  DgiiCode('02', 'Ingresos financieros'),
  DgiiCode('03', 'Ingresos extraordinarios'),
  DgiiCode('04', 'Ingresos por arrendamientos'),
  DgiiCode('05', 'Ingresos por venta de activo depreciable'),
  DgiiCode('06', 'Otros ingresos'),
];

/// La venta de un restaurante es operativa: 01.
const kDgiiDefaultIncomeType = '01';

// ── Tipo de anulación (608 col. 3) ──────────────────────────────────────────

const kDgiiVoidReasons = <DgiiCode>[
  DgiiCode('01', 'Deterioro de factura pre-impresa'),
  DgiiCode('02', 'Errores de impresión (factura pre-impresa)'),
  DgiiCode('03', 'Impresión defectuosa'),
  DgiiCode('04', 'Duplicidad de factura'),
  DgiiCode('05', 'Corrección de la información'),
  DgiiCode('06', 'Cambio de productos'),
  DgiiCode('07', 'Devolución de productos'),
  DgiiCode('08', 'Omisión de productos'),
  DgiiCode('09', 'Errores en secuencia de NCF'),
  DgiiCode('10', 'Cese de operaciones'),
  DgiiCode('11', 'Pérdida o hurto de talonarios'),
];

/// Por defecto 05: es el motivo que cubre una anulación hecha en caja para
/// corregir el comprobante, que es de lejos la más común en el POS.
const kDgiiDefaultVoidReason = '05';

/// Adivina el tipo de anulación leyendo el motivo que escribió el cajero.
/// Solo es una sugerencia: la vista deja cambiarlo antes de exportar.
String dgiiVoidReasonFrom(String? reason) {
  final r = (reason ?? '').toLowerCase();
  if (r.isEmpty) return kDgiiDefaultVoidReason;
  if (r.contains('devoluc')) return '07';
  if (r.contains('duplic')) return '04';
  if (r.contains('cambio') || r.contains('cambi')) return '06';
  if (r.contains('omis') || r.contains('falt')) return '08';
  if (r.contains('secuencia')) return '09';
  if (r.contains('impres')) return '03';
  return kDgiiDefaultVoidReason;
}
