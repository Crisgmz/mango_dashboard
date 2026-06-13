import 'package:flutter/material.dart' show DateTimeRange;

/// Clamps a desired [start]/[end] seed into the inclusive picker bounds
/// [firstDate]..[lastDate], reducing everything to date-only.
///
/// Report screens seed `showDateRangePicker` with the active period, but preset
/// periods (e.g. "este mes") carry an end that can fall in the future — handing
/// that to the picker trips its assertion that the range ends on or before
/// `lastDate`. This always returns a valid range with `start <= end`, both
/// inside the bounds.
DateTimeRange clampInitialDateRange({
  required DateTime start,
  required DateTime end,
  required DateTime firstDate,
  required DateTime lastDate,
}) {
  DateTime dayOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  final lo = dayOnly(firstDate);
  var hi = dayOnly(lastDate);
  if (hi.isBefore(lo)) hi = lo;

  var s = dayOnly(start);
  var e = dayOnly(end);
  if (s.isBefore(lo)) s = lo;
  if (e.isAfter(hi)) e = hi;
  if (e.isBefore(lo)) e = lo; // end below the whole window
  if (s.isAfter(e)) s = e;
  return DateTimeRange(start: s, end: e);
}
