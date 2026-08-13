import 'package:flutter/material.dart';

class MangoThemeFactory {
  static const Color mango = Color(0xFFF97316);
  static const Color mangoDeep = Color(0xFFEA580C);
  static const Color success = Color(0xFF22C55E);
  static const Color warning = Color(0xFFF59E0B);
  static const Color danger = Color(0xFFEF4444);
  static const Color info = Color(0xFF38BDF8);
  static const Color successDeep = Color(0xFF16A34A);
  // Métodos de pago (chips/leyendas): tarjeta azul, transferencia morada.
  static const Color payCard = Color(0xFF448AFF);
  static const Color payTransfer = Color(0xFF7C4DFF);
  // Estados apagados (cancelado, desconocido, fallback de método).
  static const Color neutral = Color(0xFF9CA3AF);
  static const Color whatsapp = Color(0xFF25D366);

  static ThemeData get lightTheme {
    const background = Color(0xFFFBFCFE);
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
        elevation: 8,
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
        labelStyle: TextStyle(color: mutedText),
        floatingLabelStyle: const TextStyle(color: mango),
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
      // Diálogos como cards blandas: fondo de card sin tinte del seed,
      // esquinas 24 — el look durazno de M3 queda prohibido.
      dialogTheme: DialogThemeData(
        backgroundColor: card,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        titleTextStyle: TextStyle(
            fontSize: 18, fontWeight: FontWeight.w700, color: text),
        contentTextStyle: TextStyle(fontSize: 14, color: text),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: background,
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: background,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
      ),
      datePickerTheme: DatePickerThemeData(
        backgroundColor: card,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
      timePickerTheme: TimePickerThemeData(
        backgroundColor: card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected) ? Colors.white : mutedText),
        trackColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected) ? mango : surfaceAlt),
        trackOutlineColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected) ? mango : border),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected)
                ? mango
                : Colors.transparent),
        side: BorderSide(color: mutedText, width: 1.6),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected) ? mango : mutedText),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: mango,
          foregroundColor: Colors.white,
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14)),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: mango,
          foregroundColor: Colors.white,
          elevation: 0,
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14)),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: mango,
          side: BorderSide(color: border),
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14)),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: mango,
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12)),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: card,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: border),
        ),
        textStyle: TextStyle(fontSize: 14, color: text),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: brightness == Brightness.light
            ? const Color(0xFF23262B)
            : surfaceAlt,
        contentTextStyle: const TextStyle(fontSize: 13.5, color: Colors.white),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      dropdownMenuTheme: DropdownMenuThemeData(
        menuStyle: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(card),
          surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
          shape: WidgetStatePropertyAll(RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: border),
          )),
        ),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(color: mango),
    );
  }

  static Color cardColor(BuildContext context) => Theme.of(context).cardColor;
  /// Fondo de tooltips de gráficas (fl_chart): claro = blanco, oscuro = gris azulado.
  static Color tooltipBackground(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? const Color(0xFF2B3138)
          : Colors.white;
  static Color borderColor(BuildContext context) => Theme.of(context).dividerColor;
  static Color altSurface(BuildContext context) => Theme.of(context).inputDecorationTheme.fillColor ?? Theme.of(context).cardColor;
  static Color mutedText(BuildContext context) => Theme.of(context).textTheme.bodySmall?.color ?? Colors.grey;
  static Color textColor(BuildContext context) => Theme.of(context).textTheme.bodyLarge?.color ?? Colors.black;
}
