/// Makes [name] safe to use as a file name for sharing/saving.
///
/// Custom-range period labels carry `/` (e.g. "1/5 - 31/5"), which the share
/// plugin treats as path separators and then fails to write (ENOENT). This
/// replaces path-illegal characters, collapses separator runs, and never
/// returns an empty string.
String sanitizeExportFilename(String name) {
  final cleaned = name
      .replaceAll(RegExp(r'[\\/:*?"<>|]+'), '-') // path-illegal → dash
      .replaceAll(RegExp(r'\s+'), '_') // whitespace → underscore
      .replaceAll(RegExp(r'[-_]{2,}'), '_'); // collapse separator runs
  final trimmed = cleaned.replaceAll(RegExp(r'^[-_]+|[-_]+$'), '');
  return trimmed.isEmpty ? 'reporte' : trimmed;
}
