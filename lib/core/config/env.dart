// lib/core/config/env.dart
import 'package:flutter/foundation.dart';

class Env {
  /// En debug (flutter run / pruebas locales) → false → usa localhost.
  /// En release (flutter build appbundle --release) → true → usa Railway.
  /// No hace falta cambiar este archivo nunca más.
  static bool get useProd => !kDebugMode;

  /// Localhost para Flutter: 10.0.2.2 = PC desde el emulador Android.
  /// En web (navegador en la misma PC) es localhost directamente.
  static String get _localBaseUrl =>
      kIsWeb ? 'http://localhost:8000' : 'http://10.0.2.2:8000';

  /// Permite forzar la URL: flutter run -d chrome --dart-define=API_BASE_URL=https://...
  static const String _overrideBaseUrl = String.fromEnvironment('API_BASE_URL');

  /// URL de producción (Railway)
  static const String _prodBaseUrl =
      'https://luckyapp-production-ca29.up.railway.app';

  /// URL final que usa toda la app
  static String get apiBaseUrl {
    if (_overrideBaseUrl.isNotEmpty) return _overrideBaseUrl;
    return useProd ? _prodBaseUrl : _localBaseUrl;
  }
}
