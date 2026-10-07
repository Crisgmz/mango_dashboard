import '../../domain/accounting/dgii_reports.dart';

/// Genera los archivos de envío de la DGII en el formato que lee el
/// prevalidador: texto plano, un registro por línea, campos separados por `|`,
/// y una cabecera con el formato, el RNC del contribuyente, el período
/// `AAAAMM` y la cantidad de registros.
///
/// Reglas del formato que se respetan aquí:
///  - Las fechas van como `AAAAMMDD`, sin separadores.
///  - Los montos van con punto decimal y dos decimales, sin separador de miles
///    y sin símbolo de moneda. Un monto en cero se manda **vacío**, no `0.00`:
///    el prevalidador rechaza ceros en las columnas que no aplican.
///  - Las columnas que el sistema no captura (ITBIS por adelantar, ISR
///    percibido, proporcionalidad del Art. 349…) van vacías, no en cero.
class DgiiTxtBuilder {
  const DgiiTxtBuilder._();

  /// 606 — Compras de bienes y servicios. 23 columnas por registro.
  static String build606({
    required String rnc,
    required DgiiPeriod period,
    required List<Dgii606Row> rows,
    required DgiiClassification classification,
  }) {
    final exportable = rows.where((r) => r.isExportable).toList(growable: false);
    final lines = <String>[
      _header('606', rnc, period, exportable.length),
      for (final r in exportable)
        [
          r.taxId ?? '', //                      1  RNC/Cédula/Pasaporte
          r.idType ?? '', //                     2  Tipo de identificación
          classification.expenseTypeFor(r), //   3  Tipo de bienes y servicios
          r.ncf ?? '', //                        4  NCF
          r.ncfModified ?? '', //                5  NCF o documento modificado
          _date(r.documentDate), //              6  Fecha comprobante
          _date(r.paymentDate), //               7  Fecha de pago
          _money(r.servicesAmount), //           8  Facturado en servicios
          _money(r.goodsAmount), //              9  Facturado en bienes
          _money(r.totalInvoiced), //           10  Total facturado
          _money(r.itbisInvoiced), //           11  ITBIS facturado
          _money(r.itbisWithheld), //           12  ITBIS retenido
          '', //                                13  ITBIS proporcionalidad (349)
          '', //                                14  ITBIS llevado al costo
          '', //                                15  ITBIS por adelantar
          '', //                                16  ITBIS percibido en compras
          '', //                                17  Tipo de retención en ISR
          _money(r.isrWithheld), //             18  Monto retención renta
          '', //                                19  ISR percibido en compras
          _money(r.isc), //                     20  Impuesto selectivo consumo
          '', //                                21  Otros impuestos/tasas
          _money(r.legalTip), //                22  Monto propina legal
          r.paymentForm, //                     23  Forma de pago
        ].join('|'),
    ];
    return lines.join('\r\n');
  }

  /// 607 — Ventas de bienes y servicios. 23 columnas por registro.
  static String build607({
    required String rnc,
    required DgiiPeriod period,
    required List<Dgii607Row> rows,
    String incomeType = '01',
  }) {
    final lines = <String>[
      _header('607', rnc, period, rows.length),
      for (final r in rows)
        [
          r.taxId ?? '', //                1  RNC/Cédula/Pasaporte
          r.idType ?? '', //               2  Tipo de identificación
          r.ncf, //                        3  NCF
          r.ncfModified ?? '', //          4  NCF modificado
          incomeType, //                   5  Tipo de ingreso
          _date(r.issuedAt), //            6  Fecha comprobante
          '', //                           7  Fecha de retención
          _money(r.amountInvoiced), //     8  Monto facturado
          _money(r.itbisInvoiced), //      9  ITBIS facturado
          '', //                          10  ITBIS retenido por terceros
          '', //                          11  ITBIS percibido
          '', //                          12  Retención renta por terceros
          '', //                          13  ISR percibido
          '', //                          14  Impuesto selectivo consumo
          '', //                          15  Otros impuestos/tasas
          _money(r.legalTip), //          16  Monto propina legal
          _money(r.cash), //              17  Efectivo
          _money(r.transfer), //          18  Cheque/Transferencia/Depósito
          _money(r.card), //              19  Tarjeta débito/crédito
          _money(r.credit), //            20  Venta a crédito
          '', //                          21  Bonos o certificados de regalo
          '', //                          22  Permuta
          _money(r.other), //             23  Otras formas de venta
        ].join('|'),
    ];
    return lines.join('\r\n');
  }

  /// 608 — Comprobantes anulados. 3 columnas por registro.
  static String build608({
    required String rnc,
    required DgiiPeriod period,
    required List<Dgii608Row> rows,
    required DgiiClassification classification,
  }) {
    final exportable = rows.where((r) => r.ncf.isNotEmpty).toList(growable: false);
    final lines = <String>[
      _header('608', rnc, period, exportable.length),
      for (final r in exportable)
        [
          r.ncf, //                           1  NCF
          _date(r.documentDate), //           2  Fecha comprobante
          classification.voidReasonFor(r), // 3  Tipo de anulación
        ].join('|'),
    ];
    return lines.join('\r\n');
  }

  /// `606|131234567|202609|48`
  static String _header(
          String format, String rnc, DgiiPeriod period, int count) =>
      [format, rnc, period.code, count.toString()].join('|');

  /// `AAAAMMDD`, o vacío si no hay fecha.
  static String _date(DateTime? value) {
    if (value == null) return '';
    final d = value.toLocal();
    return '${d.year.toString().padLeft(4, '0')}'
        '${d.month.toString().padLeft(2, '0')}'
        '${d.day.toString().padLeft(2, '0')}';
  }

  /// Dos decimales con punto, o vacío cuando es cero: el prevalidador espera la
  /// columna en blanco, no `0.00`, cuando el concepto no aplica.
  static String _money(double value) {
    if (value == 0) return '';
    return value.toStringAsFixed(2);
  }
}
