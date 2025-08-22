class Validators {
  /// ✅ Valida correo electrónico
  static String? email(String? value) {
    final v = (value ?? '').trim();
    if (v.isEmpty) return 'Ingresa tu correo electrónico.';
    final regex = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');
    if (!regex.hasMatch(v)) return 'Correo electrónico no válido.';
    return null;
  }

  /// Valida código OTP de 4 a 6 dígitos
  static String? otp(String? value) {
    final v = (value ?? '').trim();
    if (v.isEmpty) return 'Ingresa el código recibido.';
    final re = RegExp(r'^\d{4,6}$');
    if (!re.hasMatch(v)) return 'Código inválido. Debe ser de 4 a 6 dígitos.';
    return null;
  }

  /// Valida contraseña mínima de 6 (ajusta a tu política)
  static String? password(String? value) {
    final v = (value ?? '').trim();
    if (v.isEmpty) return 'Ingresa tu nueva contraseña.';
    if (v.length < 6) return 'La contraseña debe tener al menos 6 caracteres.';
    return null;
  }
}
