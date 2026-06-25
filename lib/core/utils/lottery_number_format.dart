// lib/core/utils/lottery_number_format.dart

/// Formatea el número para mostrarlo en UI.
/// - digits = 3 -> 000..999
/// - digits = 4 -> 0000..9999
/// - digits = 5 -> "0000-0" (quinta: 4 cifras + dígito extra)
String formatGameNumber(int number, int digits) {
  // 🔹 Seguridad básica
  if (digits <= 4) {
    final d = digits < 1 ? 3 : digits;
    return number.toString().padLeft(d, '0');
  }

  // ============================
  // ✅ QUINTA (digits == 5)
  // ============================

  // Quitamos cualquier guion por seguridad
  final raw = number.toString().replaceAll('-', '');

  // Siempre normalizamos a 5 dígitos
  final padded = raw.padLeft(5, '0'); // ej: "7" -> "00007"

  final main = padded.substring(0, 4); // "0000"
  final extra = padded.substring(4);  // "7"

  return '$main-$extra'; // "0000-7"
}
