import 'package:flutter_test/flutter_test.dart';
import 'package:mango_dashboard/data/accounting/dgii_txt_builder.dart';
import 'package:mango_dashboard/domain/accounting/dgii_reports.dart';

/// El TXT es lo que se sube al prevalidador de la DGII: si una columna se
/// corre, el archivo completo se rechaza. Estos tests fijan el contrato —
/// cantidad de columnas, orden, formato de fecha y el cero-como-vacío.
void main() {
  const period = DgiiPeriod(2026, 9);
  const rnc = '131234567';

  List<String> linesOf(String txt) => txt.split('\r\n');
  List<String> fieldsOf(String line) => line.split('|');

  Dgii606Row purchase({
    String? ncf = 'B0100000123',
    String? taxId = '101234567',
    String? idType = '1',
    String? supplierId = 'sup-1',
    double goods = 1000,
    double services = 0,
    double itbis = 180,
    double itbisWithheld = 0,
    double isr = 0,
    double isc = 0,
    double tip = 0,
    DateTime? documentDate,
    DateTime? paymentDate,
    String paymentForm = '01',
  }) =>
      Dgii606Row(
        receptionId: 'r1',
        supplierId: supplierId,
        supplierName: 'Distribuidora X',
        taxId: taxId,
        idType: idType,
        ncf: ncf,
        ncfModified: null,
        documentDate: documentDate ?? DateTime(2026, 9, 5),
        paymentDate: paymentDate,
        servicesAmount: services,
        goodsAmount: goods,
        itbisInvoiced: itbis,
        itbisWithheld: itbisWithheld,
        isrWithheld: isr,
        isc: isc,
        legalTip: tip,
        paymentForm: paymentForm,
      );

  Dgii607Row sale({
    String ncf = 'B0200000456',
    String? taxId,
    String? idType,
    String? ncfModified,
    double amount = 1000,
    double itbis = 180,
    double tip = 100,
    double cash = 0,
    double transfer = 0,
    double card = 1280,
    double credit = 0,
    double other = 0,
    DateTime? issuedAt,
  }) =>
      Dgii607Row(
        documentId: 'd1',
        taxId: taxId,
        idType: idType,
        ncf: ncf,
        ncfType: 'B02',
        ncfModified: ncfModified,
        customerName: 'Consumidor final',
        issuedAt: issuedAt ?? DateTime(2026, 9, 12),
        amountInvoiced: amount,
        itbisInvoiced: itbis,
        legalTip: tip,
        cash: cash,
        transfer: transfer,
        card: card,
        credit: credit,
        other: other,
      );

  Dgii608Row voided({
    String ncf = 'B0200000999',
    String? reason,
    String suggested = '05',
    DateTime? documentDate,
  }) =>
      Dgii608Row(
        documentId: 'v1',
        ncf: ncf,
        ncfType: 'B02',
        documentDate: documentDate ?? DateTime(2026, 9, 20),
        cancelledAt: DateTime(2026, 9, 21),
        total: 590,
        reason: reason,
        suggestedVoidCode: suggested,
      );

  group('cabecera', () {
    test('lleva formato, RNC, período y cantidad de registros', () {
      final txt = DgiiTxtBuilder.build607(
        rnc: rnc,
        period: period,
        rows: [sale(), sale(ncf: 'B0200000457')],
      );
      expect(linesOf(txt).first, '607|$rnc|202609|2');
    });

    test('cuenta solo los registros que de verdad se declaran', () {
      // Una compra sin NCF no puede ir en el 606 y no debe contarse.
      final txt = DgiiTxtBuilder.build606(
        rnc: rnc,
        period: period,
        rows: [purchase(), purchase(ncf: null)],
        classification: const DgiiClassification(),
      );
      expect(linesOf(txt).first, '606|$rnc|202609|1');
      expect(linesOf(txt).length, 2); // cabecera + 1 registro
    });

    test('un período sin movimiento genera solo la cabecera en cero', () {
      final txt = DgiiTxtBuilder.build608(
        rnc: rnc,
        period: period,
        rows: const [],
        classification: const DgiiClassification(),
      );
      expect(txt, '608|$rnc|202609|0');
    });
  });

  group('606', () {
    test('cada registro tiene las 23 columnas del formato', () {
      final txt = DgiiTxtBuilder.build606(
        rnc: rnc,
        period: period,
        rows: [purchase()],
        classification: const DgiiClassification(),
      );
      expect(fieldsOf(linesOf(txt)[1]).length, 23);
    });

    test('las columnas van en el orden que pide la DGII', () {
      final txt = DgiiTxtBuilder.build606(
        rnc: rnc,
        period: period,
        rows: [
          purchase(
            goods: 1000,
            services: 500,
            itbis: 270,
            itbisWithheld: 30,
            isr: 100,
            isc: 45,
            tip: 150,
            paymentDate: DateTime(2026, 9, 30),
            paymentForm: '02',
          ),
        ],
        classification: const DgiiClassification(),
      );
      final f = fieldsOf(linesOf(txt)[1]);
      expect(f[0], '101234567', reason: '1 RNC del proveedor');
      expect(f[1], '1', reason: '2 tipo de identificación');
      expect(f[2], '09', reason: '3 tipo de bien/servicio (default)');
      expect(f[3], 'B0100000123', reason: '4 NCF');
      expect(f[4], '', reason: '5 NCF modificado');
      expect(f[5], '20260905', reason: '6 fecha comprobante');
      expect(f[6], '20260930', reason: '7 fecha de pago');
      expect(f[7], '500.00', reason: '8 servicios');
      expect(f[8], '1000.00', reason: '9 bienes');
      expect(f[9], '1500.00', reason: '10 total facturado');
      expect(f[10], '270.00', reason: '11 ITBIS facturado');
      expect(f[11], '30.00', reason: '12 ITBIS retenido');
      expect(f[17], '100.00', reason: '18 retención renta');
      expect(f[19], '45.00', reason: '20 ISC');
      expect(f[21], '150.00', reason: '22 propina legal');
      expect(f[22], '02', reason: '23 forma de pago');
    });

    test('las columnas que el sistema no captura van vacías, no en cero', () {
      // 13-17 y 19, 21: proporcionalidad, costo, por adelantar, percibido,
      // tipo de retención ISR, ISR percibido y otros impuestos.
      final txt = DgiiTxtBuilder.build606(
        rnc: rnc,
        period: period,
        rows: [purchase()],
        classification: const DgiiClassification(),
      );
      final f = fieldsOf(linesOf(txt)[1]);
      for (final i in [12, 13, 14, 15, 16, 18, 20]) {
        expect(f[i], '', reason: 'columna ${i + 1} debe ir vacía');
      }
    });

    test('el total facturado es servicios + bienes', () {
      final txt = DgiiTxtBuilder.build606(
        rnc: rnc,
        period: period,
        rows: [purchase(goods: 800.55, services: 199.45)],
        classification: const DgiiClassification(),
      );
      expect(fieldsOf(linesOf(txt)[1])[9], '1000.00');
    });

    test('usa la clasificación elegida para el proveedor', () {
      final row = purchase();
      final txt = DgiiTxtBuilder.build606(
        rnc: rnc,
        period: period,
        rows: [row],
        // 03 = arrendamientos, lo típico de un proveedor de alquiler.
        classification: const DgiiClassification().withExpenseType(row, '03'),
      );
      expect(fieldsOf(linesOf(txt)[1])[2], '03');
    });

    test('deja fuera las compras sin NCF', () {
      final txt = DgiiTxtBuilder.build606(
        rnc: rnc,
        period: period,
        rows: [purchase(ncf: null), purchase(ncf: '')],
        classification: const DgiiClassification(),
      );
      expect(txt, '606|$rnc|202609|0');
    });
  });

  group('607', () {
    test('cada registro tiene las 23 columnas del formato', () {
      final txt =
          DgiiTxtBuilder.build607(rnc: rnc, period: period, rows: [sale()]);
      expect(fieldsOf(linesOf(txt)[1]).length, 23);
    });

    test('las columnas van en el orden que pide la DGII', () {
      final txt = DgiiTxtBuilder.build607(
        rnc: rnc,
        period: period,
        rows: [
          sale(
            taxId: '131234567',
            idType: '1',
            ncfModified: 'B0200000111',
            amount: 1000,
            itbis: 180,
            tip: 100,
            cash: 280,
            transfer: 500,
            card: 300,
            credit: 200,
            other: 0,
          ),
        ],
      );
      final f = fieldsOf(linesOf(txt)[1]);
      expect(f[0], '131234567', reason: '1 RNC del cliente');
      expect(f[1], '1', reason: '2 tipo de identificación');
      expect(f[2], 'B0200000456', reason: '3 NCF');
      expect(f[3], 'B0200000111', reason: '4 NCF modificado');
      expect(f[4], '01', reason: '5 tipo de ingreso');
      expect(f[5], '20260912', reason: '6 fecha comprobante');
      expect(f[6], '', reason: '7 fecha de retención');
      expect(f[7], '1000.00', reason: '8 monto facturado');
      expect(f[8], '180.00', reason: '9 ITBIS facturado');
      expect(f[15], '100.00', reason: '16 propina legal');
      expect(f[16], '280.00', reason: '17 efectivo');
      expect(f[17], '500.00', reason: '18 cheque/transferencia');
      expect(f[18], '300.00', reason: '19 tarjeta');
      expect(f[19], '200.00', reason: '20 venta a crédito');
      expect(f[22], '', reason: '23 otras formas (cero → vacío)');
    });

    test('un consumidor final va sin RNC ni tipo de identificación', () {
      final txt =
          DgiiTxtBuilder.build607(rnc: rnc, period: period, rows: [sale()]);
      final f = fieldsOf(linesOf(txt)[1]);
      expect(f[0], '');
      expect(f[1], '');
      expect(f[2], 'B0200000456', reason: 'el NCF sí va');
    });

    test('el tipo de ingreso se puede cambiar para todo el archivo', () {
      final txt = DgiiTxtBuilder.build607(
        rnc: rnc,
        period: period,
        rows: [sale()],
        incomeType: '04',
      );
      expect(fieldsOf(linesOf(txt)[1])[4], '04');
    });
  });

  group('608', () {
    test('cada registro tiene las 3 columnas del formato', () {
      final txt = DgiiTxtBuilder.build608(
        rnc: rnc,
        period: period,
        rows: [voided()],
        classification: const DgiiClassification(),
      );
      expect(fieldsOf(linesOf(txt)[1]), ['B0200000999', '20260920', '05']);
    });

    test('declara la fecha del comprobante, no la de la anulación', () {
      // El comprobante es del 20 y se anuló el 21: la DGII quiere el 20.
      final txt = DgiiTxtBuilder.build608(
        rnc: rnc,
        period: period,
        rows: [voided(documentDate: DateTime(2026, 9, 20))],
        classification: const DgiiClassification(),
      );
      expect(fieldsOf(linesOf(txt)[1])[1], '20260920');
    });

    test('usa el tipo de anulación sugerido cuando nadie lo cambió', () {
      final txt = DgiiTxtBuilder.build608(
        rnc: rnc,
        period: period,
        rows: [voided(suggested: '07')],
        classification: const DgiiClassification(),
      );
      expect(fieldsOf(linesOf(txt)[1])[2], '07');
    });

    test('lo que el usuario elige gana sobre la sugerencia', () {
      final row = voided(suggested: '07');
      final txt = DgiiTxtBuilder.build608(
        rnc: rnc,
        period: period,
        rows: [row],
        classification: const DgiiClassification().withVoidReason(row, '04'),
      );
      expect(fieldsOf(linesOf(txt)[1])[2], '04');
    });

    test('deja fuera los anulados sin NCF', () {
      final txt = DgiiTxtBuilder.build608(
        rnc: rnc,
        period: period,
        rows: [voided(ncf: '')],
        classification: const DgiiClassification(),
      );
      expect(txt, '608|$rnc|202609|0');
    });
  });

  group('formato de los valores', () {
    test('los montos llevan dos decimales y punto, sin separador de miles', () {
      final txt = DgiiTxtBuilder.build607(
        rnc: rnc,
        period: period,
        rows: [sale(amount: 1234567.5, itbis: 0.1, card: 1234567.6)],
      );
      final f = fieldsOf(linesOf(txt)[1]);
      expect(f[7], '1234567.50');
      expect(f[8], '0.10');
      expect(f.every((v) => !v.contains(',')), isTrue,
          reason: 'la coma partiría el campo en el prevalidador');
    });

    test('las fechas van AAAAMMDD con ceros a la izquierda', () {
      final txt = DgiiTxtBuilder.build607(
        rnc: rnc,
        period: const DgiiPeriod(2026, 1),
        rows: [sale(issuedAt: DateTime(2026, 1, 3))],
      );
      expect(fieldsOf(linesOf(txt)[1])[5], '20260103');
    });

    test('los registros se separan con CRLF', () {
      final txt = DgiiTxtBuilder.build607(
        rnc: rnc,
        period: period,
        rows: [sale(), sale(ncf: 'B0200000457')],
      );
      expect(txt.contains('\r\n'), isTrue);
      expect(txt.endsWith('\n'), isFalse, reason: 'sin línea vacía al final');
      expect(linesOf(txt).length, 3);
    });
  });

  group('DgiiClassification', () {
    test('la clasificación se guarda por proveedor, no por recepción', () {
      final a = purchase(supplierId: 'sup-1');
      final b = purchase(supplierId: 'sup-1', ncf: 'B0100000124');
      final c = purchase(supplierId: 'sup-2', ncf: 'B0100000125');
      final cls = const DgiiClassification().withExpenseType(a, '03');
      expect(cls.expenseTypeFor(b), '03', reason: 'mismo proveedor');
      expect(cls.expenseTypeFor(c), '09', reason: 'otro proveedor → default');
    });

    test('sin proveedor cae al nombre para no mezclar recepciones libres', () {
      final a = purchase(supplierId: null);
      final cls = const DgiiClassification().withExpenseType(a, '06');
      expect(cls.expenseTypeFor(purchase(supplierId: null)), '06');
      expect(cls.expenseTypeFor(purchase(supplierId: 'sup-9')), '09');
    });
  });
}
