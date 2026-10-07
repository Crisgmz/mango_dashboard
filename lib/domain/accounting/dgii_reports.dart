import 'package:flutter/foundation.dart' show immutable;

import 'dgii_catalogs.dart';

/// Modelos de los tres formatos de envío de la DGII que el dashboard genera:
/// 606 (compras), 607 (ventas) y 608 (comprobantes anulados).
///
/// Cada fila guarda **solo** lo que el sistema sabe; las columnas de criterio
/// contable (tipo de bien/servicio en el 606, tipo de anulación en el 608)
/// viven aparte en [DgiiClassification] porque las decide el usuario antes de
/// exportar. Los montos van en `double` y se formatean al escribir el TXT.

/// Período de envío. La DGII pide un archivo por mes, con el período en la
/// cabecera como `AAAAMM`.
@immutable
class DgiiPeriod {
  const DgiiPeriod(this.year, this.month);

  factory DgiiPeriod.of(DateTime date) => DgiiPeriod(date.year, date.month);

  final int year;
  final int month;

  /// `202609` — lo que va en la cabecera del archivo.
  String get code => '$year${month.toString().padLeft(2, '0')}';

  /// Primer instante del mes (local): inicio del rango de consulta.
  DateTime get start => DateTime(year, month, 1);

  /// Primer instante del mes siguiente: el rango es `[start, end)`.
  DateTime get end => month == 12 ? DateTime(year + 1, 1, 1) : DateTime(year, month + 1, 1);

  /// `Septiembre 2026`.
  String get label => '${_monthNames[month - 1]} $year';

  /// `Sep 2026` — para títulos estrechos y nombres de archivo.
  String get shortLabel => '${_monthNames[month - 1].substring(0, 3)} $year';

  DgiiPeriod get previous => month == 1 ? DgiiPeriod(year - 1, 12) : DgiiPeriod(year, month - 1);

  DgiiPeriod get next => month == 12 ? DgiiPeriod(year + 1, 1) : DgiiPeriod(year, month + 1);

  /// Un período es futuro cuando su mes todavía no empezó.
  bool isAfter(DgiiPeriod other) =>
      year > other.year || (year == other.year && month > other.month);

  @override
  bool operator ==(Object other) =>
      other is DgiiPeriod && other.year == year && other.month == month;

  @override
  int get hashCode => Object.hash(year, month);

  static const _monthNames = [
    'Enero', 'Febrero', 'Marzo', 'Abril', 'Mayo', 'Junio',
    'Julio', 'Agosto', 'Septiembre', 'Octubre', 'Noviembre', 'Diciembre',
  ];
}

/// Fila del **606 — Compras de bienes y servicios**. Sale de
/// `purchase_receptions`, que se creó con el bloque fiscal del 606
/// (migración 20260811_0002), unida al proveedor por su RNC.
@immutable
class Dgii606Row {
  const Dgii606Row({
    required this.receptionId,
    required this.supplierId,
    required this.supplierName,
    required this.taxId,
    required this.idType,
    required this.ncf,
    required this.ncfModified,
    required this.documentDate,
    required this.paymentDate,
    required this.servicesAmount,
    required this.goodsAmount,
    required this.itbisInvoiced,
    required this.itbisWithheld,
    required this.isrWithheld,
    required this.isc,
    required this.legalTip,
    required this.paymentForm,
  });

  final String receptionId;
  final String? supplierId;
  final String supplierName;

  /// RNC / cédula / pasaporte del proveedor (solo dígitos cuando aplica).
  final String? taxId;

  /// `1` | `2` | `3`, o null cuando el proveedor no tiene identificación.
  final String? idType;

  final String? ncf;

  /// NCF afectado por una nota de crédito/débito de compra.
  final String? ncfModified;

  final DateTime? documentDate;
  final DateTime? paymentDate;

  final double servicesAmount;
  final double goodsAmount;
  final double itbisInvoiced;
  final double itbisWithheld;
  final double isrWithheld;
  final double isc;
  final double legalTip;

  /// Código 01–07 del 606, ya traducido desde `payment_method`.
  final String paymentForm;

  double get totalInvoiced => servicesAmount + goodsAmount;

  /// Una fila sin NCF no puede ir en el 606: la DGII lo exige. La vista la
  /// muestra igual, marcada, para que el usuario sepa qué recepción corregir.
  bool get isExportable => (ncf ?? '').trim().isNotEmpty;
}

/// Fila del **607 — Ventas de bienes y servicios**. Sale de
/// `fiscal_documents` (un comprobante = una fila) con el desglose de cobro
/// tomado de `payments` del mismo pedido o división.
@immutable
class Dgii607Row {
  const Dgii607Row({
    required this.documentId,
    required this.taxId,
    required this.idType,
    required this.ncf,
    required this.ncfType,
    required this.ncfModified,
    required this.customerName,
    required this.issuedAt,
    required this.amountInvoiced,
    required this.itbisInvoiced,
    required this.legalTip,
    required this.cash,
    required this.transfer,
    required this.card,
    required this.credit,
    required this.other,
  });

  final String documentId;
  final String? taxId;
  final String? idType;
  final String ncf;
  final String ncfType;

  /// NCF que este comprobante modifica (nota de crédito/débito).
  final String? ncfModified;

  final String? customerName;
  final DateTime issuedAt;

  /// Monto facturado SIN ITBIS ni propina legal (col. 8).
  final double amountInvoiced;

  final double itbisInvoiced;

  /// Propina legal — `fiscal_documents.service_fee` (col. 16).
  final double legalTip;

  // Desglose por forma de venta (cols. 17–23).
  final double cash;
  final double transfer;
  final double card;
  final double credit;
  final double other;

  double get total => amountInvoiced + itbisInvoiced + legalTip;

  double get paymentsTotal => cash + transfer + card + credit + other;

  /// El desglose de cobro no cuadra con el total facturado (redondeo aparte).
  /// Pasa cuando el comprobante se emitió por una división y los pagos quedaron
  /// colgando del pedido completo: la vista lo marca para revisarlo.
  bool get paymentsMismatch => (paymentsTotal - total).abs() > 1.0;
}

/// Fila del **608 — Comprobantes anulados**. Tres columnas: NCF, fecha y tipo
/// de anulación.
@immutable
class Dgii608Row {
  const Dgii608Row({
    required this.documentId,
    required this.ncf,
    required this.ncfType,
    required this.documentDate,
    required this.cancelledAt,
    required this.total,
    required this.reason,
    required this.suggestedVoidCode,
  });

  final String documentId;
  final String ncf;
  final String ncfType;

  /// Fecha del comprobante, que es la que pide la DGII (no la de anulación).
  final DateTime documentDate;

  final DateTime? cancelledAt;

  /// Monto que llevaba el comprobante anulado. No va en el archivo; se muestra
  /// para que el usuario reconozca cuál es.
  final double total;

  /// Motivo en texto libre que escribió quien anuló.
  final String? reason;

  /// Código 01–11 deducido del [reason]. Es la propuesta inicial.
  final String suggestedVoidCode;
}

/// Clasificación que el usuario decide antes de exportar, porque el sistema no
/// la registra: el tipo de bien/servicio de cada compra (606) y el tipo de
/// anulación de cada comprobante (608).
///
/// Las llaves son estables a propósito — proveedor para el 606 (la
/// clasificación de un proveedor no cambia mes a mes) y NCF para el 608 — para
/// poder recordarlas entre sesiones.
@immutable
class DgiiClassification {
  const DgiiClassification({
    this.expenseTypeBySupplier = const {},
    this.voidReasonByNcf = const {},
  });

  /// `supplier_id` (o el nombre, si la recepción no trae proveedor) → código
  /// del catálogo [kDgiiExpenseTypes].
  final Map<String, String> expenseTypeBySupplier;

  /// NCF → código del catálogo [kDgiiVoidReasons].
  final Map<String, String> voidReasonByNcf;

  String expenseTypeFor(Dgii606Row row) =>
      expenseTypeBySupplier[_supplierKey(row)] ?? kDgiiDefaultExpenseType;

  String voidReasonFor(Dgii608Row row) =>
      voidReasonByNcf[row.ncf] ?? row.suggestedVoidCode;

  DgiiClassification withExpenseType(Dgii606Row row, String code) =>
      DgiiClassification(
        expenseTypeBySupplier: {...expenseTypeBySupplier, _supplierKey(row): code},
        voidReasonByNcf: voidReasonByNcf,
      );

  DgiiClassification withVoidReason(Dgii608Row row, String code) =>
      DgiiClassification(
        expenseTypeBySupplier: expenseTypeBySupplier,
        voidReasonByNcf: {...voidReasonByNcf, row.ncf: code},
      );

  static String _supplierKey(Dgii606Row row) =>
      row.supplierId ?? 'name:${row.supplierName}';
}
