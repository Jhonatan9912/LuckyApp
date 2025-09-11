// lib/presentation/providers/notifications_provider.dart
//
// Orquesta el registro del device_token en tu backend,
// escucha la renovación de token de FCM y expone hooks
// para login/logout desde tu flujo de autenticación.

import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import 'package:base_app/core/notifications/fcm_messaging.dart';
import 'package:base_app/data/api/notifications_api.dart';
import 'package:base_app/core/network/api_client.dart';
import 'package:base_app/data/session/session_manager.dart';
import 'package:base_app/core/config/env.dart';

class NotificationsProvider extends ChangeNotifier {
  final NotificationsApi api;
  final SessionManager session;

  NotificationsProvider({
    required this.api,
    required this.session,
  });

  String? _currentToken;
  StreamSubscription<String>? _refreshSub;

  String? get currentToken => _currentToken;

  /// Inicializa la suscripción a onTokenRefresh.
  /// Llamar una sola vez en el arranque de la app (post-login también sirve).
  Future<void> init() async {
    // Toma el token actual de FCM (si existe)
    _currentToken =
        FcmMessaging.I.currentToken ?? await FirebaseMessaging.instance.getToken();

    // Suscripción a la renovación de token
    _refreshSub?.cancel();
    _refreshSub =
        FirebaseMessaging.instance.onTokenRefresh.listen((token) async {
      _currentToken = token;
      if (kDebugMode) {
        debugPrint('[NotificationsProvider] onTokenRefresh: $token');
      }

      // Si el usuario está autenticado, re-registra token en backend
      if (await _isAuthenticated()) {
        await _safeRegisterToken(token);
      }
      notifyListeners();
    });
  }

  /// Hook para tu flujo de login: cuando el usuario queda autenticado,
  /// registra (o actualiza) el token en el backend.
  Future<void> onUserAuthenticated() async {
    // Asegura inicialización
    await init();

    // Si hay token y sesión válida, registra
    final token =
        _currentToken ?? await FirebaseMessaging.instance.getToken();
    if (token != null && await _isAuthenticated()) {
      await _safeRegisterToken(token);
    }
  }

  /// Hook para logout: elimina el token del backend (solo este dispositivo).
  Future<void> onUserLoggedOut() async {
    final token = _currentToken;
    if (token != null) {
      try {
        await api.deleteToken(token: token);
      } catch (e) {
        if (kDebugMode) {
          debugPrint('[NotificationsProvider] deleteToken error: $e');
        }
      }
    }
  }

  /// Limpia recursos
  @override
  void dispose() {
    _refreshSub?.cancel();
    super.dispose();
  }

  // ================== Helpers internos ==================

  Future<void> _safeRegisterToken(String token) async {
    try {
      final platform = _platformString();
      await api.registerToken(token: token, platform: platform);
      if (kDebugMode) {
        debugPrint('[NotificationsProvider] token registrado ($platform)');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[NotificationsProvider] registerToken error: $e');
      }
    }
  }

  Future<bool> _isAuthenticated() async {
    // Consideramos autenticado si existe un bearer/token en SessionManager.
    final token = await session.getToken(); // <-- usar getToken()
    return token != null && token.isNotEmpty;
  }

  String _platformString() {
    if (kIsWeb) return 'web';
    if (Platform.isAndroid) return 'android';
    if (Platform.isIOS) return 'ios';
    return 'unknown';
  }
}

/// Factory sencilla para construir NotificationsProvider con las
/// dependencias reales de tu app (ApiClient + SessionManager).
NotificationsProvider buildNotificationsProvider({
  required ApiClient apiClient,
  required SessionManager session,
}) {
  return NotificationsProvider(
    api: NotificationsApi(
      baseUrl: Env.apiBaseUrl,
      apiClient: apiClient,
      session: session,
    ),
    session: session,
  );
}
