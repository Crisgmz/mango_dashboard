import 'package:flutter_test/flutter_test.dart';
import 'package:mango_dashboard/core/formatters/mango_formatters.dart';

/// Monto escrito a mano en el diálogo de ingreso de caja. Todo lo que el app
/// muestra es en_US, así que la coma es separador de miles: si se leyera como
/// decimal, un ingreso de "10,000" entraría a la caja como RD$ 10.
void main() {
  test('la coma es separador de miles, no decimal', () {
    expect(MangoFormatters.parsePositiveAmount('10,000'), 10000);
    expect(MangoFormatters.parsePositiveAmount('10,500.50'), 10500.5);
    expect(MangoFormatters.parsePositiveAmount('1,234,567.89'), 1234567.89);
  });

  test('acepta lo que se escribe sin adornos', () {
    expect(MangoFormatters.parsePositiveAmount('1500'), 1500);
    expect(MangoFormatters.parsePositiveAmount('1500.75'), 1500.75);
    expect(MangoFormatters.parsePositiveAmount(' 200 '), 200);
    expect(MangoFormatters.parsePositiveAmount('RD\$ 3,000'), 3000);
  });

  test('rechaza lo que no es un monto positivo', () {
    expect(MangoFormatters.parsePositiveAmount(''), isNull);
    expect(MangoFormatters.parsePositiveAmount('   '), isNull);
    expect(MangoFormatters.parsePositiveAmount('0'), isNull);
    expect(MangoFormatters.parsePositiveAmount('-50'), isNull);
    expect(MangoFormatters.parsePositiveAmount('abc'), isNull);
    expect(MangoFormatters.parsePositiveAmount('1.2.3'), isNull);
  });
}
