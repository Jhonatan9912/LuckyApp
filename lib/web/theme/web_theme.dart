// lib/web/theme/web_theme.dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'web_palette.dart';

/// Tema oscuro para las pantallas rediseñadas de la web.
ThemeData buildWebTheme() {
  final base = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: const ColorScheme.dark(
      primary: WebPalette.gold,
      onPrimary: Color(0xFF1A1300),
      secondary: WebPalette.goldLight,
      surface: WebPalette.surface,
      onSurface: WebPalette.text,
      error: WebPalette.danger,
    ),
    scaffoldBackgroundColor: WebPalette.bg,
  );

  OutlineInputBorder border(Color c, [double w = 1]) => OutlineInputBorder(
    borderRadius: BorderRadius.circular(14),
    borderSide: BorderSide(color: c, width: w),
  );

  return base.copyWith(
    textTheme: GoogleFonts.plusJakartaSansTextTheme(
      base.textTheme,
    ).apply(bodyColor: WebPalette.text, displayColor: WebPalette.text),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white.withValues(alpha: 0.04),
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
      labelStyle: WebPalette.body(14, color: WebPalette.textMuted),
      floatingLabelStyle: WebPalette.body(
        14,
        color: WebPalette.goldLight,
        weight: FontWeight.w600,
      ),
      hintStyle: WebPalette.body(14, color: WebPalette.textFaint),
      prefixIconColor: WebPalette.textMuted,
      suffixIconColor: WebPalette.textMuted,
      border: border(WebPalette.glassBorder),
      enabledBorder: border(WebPalette.glassBorder),
      focusedBorder: border(WebPalette.gold, 1.4),
      errorBorder: border(WebPalette.danger),
      focusedErrorBorder: border(WebPalette.danger, 1.4),
    ),
    checkboxTheme: CheckboxThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      side: BorderSide(color: WebPalette.textFaint, width: 1.4),
      fillColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected)
            ? WebPalette.gold
            : Colors.transparent,
      ),
      checkColor: const WidgetStatePropertyAll(Color(0xFF1A1300)),
    ),
    textSelectionTheme: const TextSelectionThemeData(
      cursorColor: WebPalette.gold,
      selectionColor: Color(0x55D4AF37),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: WebPalette.bgElevated,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: WebPalette.glassBorder),
      ),
    ),
    datePickerTheme: DatePickerThemeData(
      backgroundColor: WebPalette.bgElevated,
      headerBackgroundColor: WebPalette.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: WebPalette.surface,
      contentTextStyle: WebPalette.body(14, color: WebPalette.text),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      width: 420,
    ),
    dropdownMenuTheme: DropdownMenuThemeData(
      menuStyle: MenuStyle(
        backgroundColor: const WidgetStatePropertyAll(WebPalette.bgElevated),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: WebPalette.gold,
    ),
  );
}
