// lib/core/config/constants.dart  (o donde esté)
import 'package:base_app/core/config/env.dart';

class Constants {
  // Usa SIEMPRE la URL que definimos en Env (se puede override con --dart-define)
  static const apiBaseUrl = Env.apiBaseUrl;
  // Opcional: si prefieres no const:
  // static String get apiBaseUrl => Env.apiBaseUrl;
}
