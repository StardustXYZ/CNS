import 'package:flutter/material.dart';

/// The colours of the web app (web/style.css), so the two look the same.
abstract final class CnsColors {
  static const background = Color(0xFF0B0B0B);
  static const bar = Color(0xFF000000); // title bar and bottom menu, as the web navbar
  static const surface = Color(0xFF161616);
  static const surface2 = Color(0xFF222222);
  static const border = Color(0xFF333333);
  static const text = Color(0xFFE6E6E6);
  static const textMuted = Color(0xFF9A9A9A);
  static const green = Color(0xFF008000); // CNS green: icon, buttons (white text on it)
  static const accent = Color(0xFF33A833); // the same green, lighter: small text and icons on black
  static const yellow = Color(0xFFFF9800);
  static const red = Color(0xFFF44336);
}

ThemeData cnsTheme() {
  const scheme = ColorScheme.dark(
    primary: CnsColors.green,
    onPrimary: Colors.white,
    secondary: CnsColors.accent,
    onSecondary: Colors.black,
    surface: CnsColors.surface,
    onSurface: CnsColors.text,
    error: CnsColors.red,
  );
  Color selectedOr(Set<WidgetState> states, Color other) =>
      states.contains(WidgetState.selected) ? CnsColors.accent : other;
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: CnsColors.background,
    dividerColor: CnsColors.border,
    appBarTheme: const AppBarTheme(
      backgroundColor: CnsColors.bar,
      foregroundColor: CnsColors.text,
      elevation: 0,
      scrolledUnderElevation: 0,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: CnsColors.bar,
      indicatorColor: CnsColors.green.withValues(alpha: 0.35),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => TextStyle(
          fontSize: 12,
          color: selectedOr(states, CnsColors.textMuted),
          fontWeight: states.contains(WidgetState.selected) ? FontWeight.w600 : FontWeight.w400,
        ),
      ),
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(color: selectedOr(states, CnsColors.textMuted)),
      ),
    ),
  );
}
