import 'package:flutter/material.dart';

class MangoThemeFactory {
  static const Color mango = Color(0xFFF97316);
  static const Color mangoDeep = Color(0xFFEA580C);
  static const Color success = Color(0xFF22C55E);
  static const Color warning = Color(0xFFF59E0B);
  static const Color danger = Color(0xFFEF4444);
  static const Color info = Color(0xFF38BDF8);

  static ThemeData get lightTheme {
    const background = Color(0xFFF6F7F9);
    const surface = Color(0xFFFFFFFF);
    const surfaceAlt = Color(0xFFF1F3F6);
    const card = Color(0xFFFFFFFF);
    const text = Color(0xFF171A1F);
    const mutedText = Color(0xFF6B7280);
    const border = Color(0xFFE5E7EB);

    return _build(
      brightness: Brightness.light,
      background: background,
      surface: surface,
      surfaceAlt: surfaceAlt,
      card: card,
      text: text,
      mutedText: mutedText,
      border: border,
    );
  }

  static ThemeData get darkTheme {
    const background = Color(0xFF111315);
    const surface = Color(0xFF191C20);
    const surfaceAlt = Color(0xFF22262B);
    const card = Color(0xFF1A1D21);
    const text = Color(0xFFF7F8FA);
    const mutedText = Color(0xFFA5ADB8);
    const border = Color(0xFF2B3138);

    return _build(
      brightness: Brightness.dark,
      background: background,
      surface: surface,
      surfaceAlt: surfaceAlt,
      card: card,
      text: text,
      mutedText: mutedText,
      border: border,
    );
  }

  static ThemeData _build({
    required Brightness brightness,
    required Color background,
    required Color surface,
    required Color surfaceAlt,
    required Color card,
    required Color text,
    required Color mutedText,
    required Color border,
  }) {
    final scheme = ColorScheme.fromSeed(
      seedColor: mango,
      brightness: brightness,
      primary: mango,
      secondary: warning,
      surface: surface,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      scaffoldBackgroundColor: background,
      colorScheme: scheme,
      cardColor: card,
      dividerColor: border,
      appBarTheme: AppBarTheme(
        backgroundColor: background,
        elevation: 0,
        foregroundColor: text,
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: surface,
        selectedItemColor: mango,
        unselectedItemColor: mutedText,
        type: BottomNavigationBarType.fixed,
      ),
      textTheme: TextTheme(
        headlineMedium: TextStyle(fontSize: 28, fontWeight: FontWeight.w700, color: text),
        titleLarge: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: text),
        titleMedium: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: text),
        bodyLarge: TextStyle(fontSize: 15, color: text),
        bodyMedium: TextStyle(fontSize: 14, color: text),
        bodySmall: TextStyle(fontSize: 13, color: mutedText),
        labelLarge: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: text),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceAlt,
        hintStyle: TextStyle(color: mutedText),
        prefixIconColor: mutedText,
        suffixIconColor: mutedText,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: mango, width: 1.2),
        ),
      ),
    );
  }

  static Color cardColor(BuildContext context) => Theme.of(context).cardColor;
  static Color borderColor(BuildContext context) => Theme.of(context).dividerColor;
  static Color altSurface(BuildContext context) => Theme.of(context).inputDecorationTheme.fillColor ?? Theme.of(context).cardColor;
  static Color mutedText(BuildContext context) => Theme.of(context).textTheme.bodySmall?.color ?? Colors.grey;
  static Color textColor(BuildContext context) => Theme.of(context).textTheme.bodyLarge?.color ?? Colors.black;
}
