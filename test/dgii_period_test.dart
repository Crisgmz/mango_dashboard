import 'package:flutter_test/flutter_test.dart';
import 'package:mango_dashboard/domain/accounting/dgii_catalogs.dart';
import 'package:mango_dashboard/domain/accounting/dgii_reports.dart';

/// El período de los envíos DGII es un mes completo, y su código `AAAAMM` es lo
/// que va en la cabecera del archivo. Los bordes de año son donde esto se rompe
/// si está mal.
void main() {
  group('DgiiPeriod', () {
    test('el código es AAAAMM con el mes a dos dígitos', () {
      expect(const DgiiPeriod(2026, 9).code, '202609');
      expect(const DgiiPeriod(2026, 12).code, '202612');
      expect(const DgiiPeriod(2026, 1).code, '202601');
    });

    test('el rango es [primer día del mes, primer día del siguiente)', () {
      const p = DgiiPeriod(2026, 2);
      expect(p.start, DateTime(2026, 2, 1));
      expect(p.end, DateTime(2026, 3, 1));
    });

    test('diciembre cierra contra enero del año siguiente', () {
      const dec = DgiiPeriod(2026, 12);
      expect(dec.end, DateTime(2027, 1, 1));
      expect(dec.next, const DgiiPeriod(2027, 1));
    });

    test('enero retrocede a diciembre del año anterior', () {
      expect(const DgiiPeriod(2026, 1).previous, const DgiiPeriod(2025, 12));
    });

    test('isAfter compara año y mes, no solo el mes', () {
      expect(const DgiiPeriod(2027, 1).isAfter(const DgiiPeriod(2026, 12)), isTrue);
      expect(const DgiiPeriod(2026, 12).isAfter(const DgiiPeriod(2027, 1)), isFalse);
      expect(const DgiiPeriod(2026, 9).isAfter(const DgiiPeriod(2026, 9)), isFalse);
    });

    test('el mes por defecto es el anterior al actual', () {
      // Es lo que vence el 20 de este mes; no se declara el mes en curso.
      final now = DateTime(2026, 1, 15);
      expect(DgiiPeriod.of(now).previous, const DgiiPeriod(2025, 12));
    });
  });

  group('tipo de identificación', () {
    test('9 dígitos es RNC y 11 es cédula', () {
      expect(dgiiIdTypeFor('131234567'), '1');
      expect(dgiiIdTypeFor('40212345678'), '2');
    });

    test('ignora guiones y espacios al medir el largo', () {
      expect(dgiiIdTypeFor('1-31-23456-7'), '1');
      expect(dgiiIdTypeFor('402 1234 5678'), '2');
    });

    test('sin identificación no devuelve tipo: la columna va vacía', () {
      expect(dgiiIdTypeFor(null), isNull);
      expect(dgiiIdTypeFor(''), isNull);
      expect(dgiiIdTypeFor('   '), isNull);
    });

    test('lo declarado en el proveedor manda sobre la forma del número', () {
      // Una cédula de 11 escrita en el campo rnc, marcada como cédula.
      expect(dgiiIdTypeFor('40212345678', declaredType: 'cedula'), '2');
      // Y un pasaporte queda como pasaporte aunque traiga 9 dígitos.
      expect(dgiiIdTypeFor('123456789', declaredType: 'pasaporte'), '3');
    });

    test('un número con letras es pasaporte', () {
      expect(dgiiIdTypeFor('AB123456'), '3');
    });
  });

  group('forma de pago del 606', () {
    test('traduce los códigos del POS al catálogo de la DGII', () {
      expect(dgiiPurchasePaymentForm('cash'), '01');
      expect(dgiiPurchasePaymentForm('transfer'), '02');
      expect(dgiiPurchasePaymentForm('card'), '03');
      expect(dgiiPurchasePaymentForm('credit'), '04');
    });

    test('acepta el texto en español que pudo guardar la recepción', () {
      expect(dgiiPurchasePaymentForm('Efectivo'), '01');
      expect(dgiiPurchasePaymentForm('TRANSFERENCIA'), '02');
      expect(dgiiPurchasePaymentForm('Crédito'), '04');
    });

    test('lo desconocido cae en efectivo, no en vacío', () {
      // La columna 23 es obligatoria: dejarla vacía invalida el registro.
      expect(dgiiPurchasePaymentForm(null), '01');
      expect(dgiiPurchasePaymentForm('loquesea'), '01');
    });
  });

  group('tipo de anulación sugerido para el 608', () {
    test('reconoce los motivos típicos de caja', () {
      expect(dgiiVoidReasonFrom('Devolución de productos'), '07');
      expect(dgiiVoidReasonFrom('factura duplicada'), '04');
      expect(dgiiVoidReasonFrom('el cliente pidió cambio de producto'), '06');
      expect(dgiiVoidReasonFrom('faltó un producto, omisión'), '08');
    });

    test('sin motivo cae en corrección de la información', () {
      expect(dgiiVoidReasonFrom(null), '05');
      expect(dgiiVoidReasonFrom(''), '05');
      expect(dgiiVoidReasonFrom('cualquier otra cosa'), '05');
    });
  });

  group('dgiiCodeOf', () {
    test('encuentra la etiqueta de un código del catálogo', () {
      expect(dgiiCodeOf(kDgiiExpenseTypes, '09')?.label,
          'Compras y gastos que forman parte del costo de venta');
      expect(dgiiCodeOf(kDgiiVoidReasons, '07')?.label,
          'Devolución de productos');
    });

    test('devuelve null para un código que no existe', () {
      expect(dgiiCodeOf(kDgiiExpenseTypes, '99'), isNull);
      expect(dgiiCodeOf(kDgiiExpenseTypes, null), isNull);
    });
  });
}
