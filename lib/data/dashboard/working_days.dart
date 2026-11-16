/// Días laborables del negocio: qué días de la semana abre, para que las
/// proyecciones del mes solo cuenten esos días.
///
/// Convención de [DateTime.weekday]: 1 = lunes … 7 = domingo.
const Set<int> kAllWeekdays = {1, 2, 3, 4, 5, 6, 7};

const List<String> kWeekdayShortEs = ['Lun', 'Mar', 'Mié', 'Jue', 'Vie', 'Sáb', 'Dom'];
const List<String> _weekdayLongEs = [
  'lunes', 'martes', 'miércoles', 'jueves', 'viernes', 'sábado', 'domingo',
];

/// Un conjunto vacío o con valores fuera de 1..7 no tiene sentido para
/// proyectar; se trata como "todos los días".
Set<int> normalizeWorkingDays(Iterable<int> days) {
  final valid = days.where((d) => d >= 1 && d <= 7).toSet();
  return valid.isEmpty ? kAllWeekdays : valid;
}

/// Días laborables del mes: [total] en el mes completo y [elapsed] del día 1
/// hasta [throughDay] inclusive (null = mes completo, para meses pasados).
({int elapsed, int total}) monthWorkingDays({
  required int year,
  required int month,
  required Set<int> workingDays,
  int? throughDay,
}) {
  final days = normalizeWorkingDays(workingDays);
  final daysInMonth = DateTime(year, month + 1, 0).day;
  final through = (throughDay ?? daysInMonth).clamp(0, daysInMonth);
  var total = 0;
  var elapsed = 0;
  for (var d = 1; d <= daysInMonth; d++) {
    if (!days.contains(DateTime(year, month, d).weekday)) continue;
    total++;
    if (d <= through) elapsed++;
  }
  return (elapsed: elapsed, total: total);
}

/// Texto corto para mostrar la selección: "Todos los días", "Lunes a sábado",
/// "Jueves a lunes", "Sábado y domingo", "Solo viernes" o "Lun, Mié, Vie".
String workingDaysLabel(Set<int> workingDays) {
  final days = normalizeWorkingDays(workingDays);
  if (days.length == 7) return 'Todos los días';
  if (days.length == 1) return 'Solo ${_weekdayLongEs[days.first - 1]}';

  // ¿Es un solo tramo seguido (admite cruzar el domingo → lunes)?
  for (var start = 1; start <= 7; start++) {
    final prev = start == 1 ? 7 : start - 1;
    if (!days.contains(start) || days.contains(prev)) continue;
    var end = start;
    var count = 1;
    while (count < days.length && days.contains(end % 7 + 1)) {
      end = end % 7 + 1;
      count++;
    }
    if (count == days.length) {
      final from = _weekdayLongEs[start - 1];
      final to = _weekdayLongEs[end - 1];
      final first = from[0].toUpperCase() + from.substring(1);
      return days.length == 2 ? '$first y $to' : '$first a $to';
    }
    break;
  }

  final sorted = days.toList()..sort();
  return sorted.map((d) => kWeekdayShortEs[d - 1]).join(', ');
}
