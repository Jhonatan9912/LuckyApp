// lib/core/config/env.dart
import 'package:flutter/foundation.dart';

class Env {
  /// En debug (flutter run / pruebas locales) → false → usa localhost.
  /// En release (flutter build appbundle --release) → true → usa Railway.
  /// No hace falta cambiar este archivo nunca más.
  static bool get useProd => !kDebugMode;

  /// Localhost para Flutter: 10.0.2.2 = PC desde el emulador Android
  static const String _localBaseUrl = 'http://10.0.2.2:8000';

  /// URL de producción (Railway)
  static const String _prodBaseUrl =
      'https://luckyapp-production-ca29.up.railway.app';

  /// URL final que usa toda la app
  static String get apiBaseUrl =>
      useProd ? _prodBaseUrl : _localBaseUrl;
}
