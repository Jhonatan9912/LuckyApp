// lib/web/theme/web_palette.dart
//
// Paleta de la versión web: lujo oscuro con acentos dorados.
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class WebPalette {
  WebPalette._();

  // Fondos
  static const Color bg = Color(0xFF07070B);
  static const Color bgElevated = Color(0xFF0F0F16);
  static const Color surface = Color(0xFF15151F);

  // Dorados
  static const Color gold = Color(0xFFD4AF37);
  static const Color goldLight = Color(0xFFF6E27A);
  static const Color goldDeep = Color(0xFFA67C00);
  static const Color amber = Color(0xFFFFB300);

  // Acentos de ambiente
  static const Color violet = Color(0xFF6D3BFF);
  static const Color emerald = Color(0xFF19C37D);
  static const Color danger = Color(0xFFFF5A5F);

  // Texto
  static const Color text = Color(0xFFF5F3EE);
  static const Color textMuted = Color(0xFFA9A6B5);
  static const Color textFaint = Color(0xFF6E6B7B);

  // Vidrio
  static Color glass = Colors.white.withValues(alpha: 0.045);
  static Color glassBorder = Colors.white.withValues(alpha: 0.09);

  static const LinearGradient goldGradient = LinearGradient(
    colors: [goldLight, gold, goldDeep],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient goldTextGradient = LinearGradient(
    colors: [Color(0xFFFFF1B8), goldLight, gold, Color(0xFFE8B931)],
  );

  /// Tipografía de títulos (display).
  static TextStyle display(
    double size, {
    FontWeight weight = FontWeight.w700,
    Color color = text,
    double? height,
  }) => GoogleFonts.sora(
    fontSize: size,
    fontWeight: weight,
    color: color,
    height: height ?? 1.1,
    letterSpacing: -0.02 * size,
  );

  /// Tipografía de cuerpo.
  static TextStyle body(
    double size, {
    FontWeight weight = FontWeight.w400,
    Color color = textMuted,
    double? height,
  }) => GoogleFonts.plusJakartaSans(
    fontSize: size,
    fontWeight: weight,
    color: color,
    height: height ?? 1.5,
  );
}
