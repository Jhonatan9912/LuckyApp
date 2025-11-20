// lib/core/config/env.dart

class Env {
  /// Cambia esto a true cuando quieras usar Railway / Producción.
  static const bool useProd = false;

  /// Localhost para Flutter: 10.0.2.2 = PC desde el emulador Android
  static const String _localBaseUrl = 'http://10.0.2.2:8000';

  /// URL de producción (Railway)
  static const String _prodBaseUrl =
      'https://luckyapp-production-ca29.up.railway.app';

  /// URL final que usa toda la app
  static String get apiBaseUrl =>
      useProd ? _prodBaseUrl : _localBaseUrl;
}
