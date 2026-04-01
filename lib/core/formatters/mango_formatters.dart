import 'package:intl/intl.dart';

class MangoFormatters {
  static final NumberFormat _currency = NumberFormat.currency(
    locale: 'en_US',
    symbol: 'RD\$ ',
    decimalDigits: 2,
  );

  static final NumberFormat _number = NumberFormat.decimalPattern('en_US');

  static String currency(num value) => _currency.format(value);

  static String number(num value) => _number.format(value);
}
