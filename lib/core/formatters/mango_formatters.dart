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

  static String dateTime(DateTime value) => DateFormat('dd/MM/yyyy HH:mm').format(value.toLocal());

  static String fullDate(DateTime value) {
    final now = DateTime.now();
    final local = value.toLocal();
    if (local.year == now.year && local.month == now.month && local.day == now.day) {
      return 'Hoy ${DateFormat('HH:mm').format(local)}';
    }
    return DateFormat('dd/MM HH:mm').format(local);
  }
}
