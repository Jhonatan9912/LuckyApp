// lib/data/api/notifications_api.dart
//
// API para registrar, eliminar y (opcional) enviar prueba de notificación
// del dispositivo en el backend. Usa ApiClient y SessionManager existentes.

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:base_app/core/network/api_client.dart';
import 'package:base_app/data/session/session_manager.dart';

class NotificationsApi {
  final String baseUrl;
  final ApiClient apiClient;
  final SessionManager session;

  NotificationsApi({
    required this.baseUrl,
    required this.apiClient,
    required this.session,
  });

  /// Registra o actualiza el token del dispositivo en el backend.
  /// `platform`: 'android' | 'ios' | 'web'
  Future<void> registerToken({
    required String token,
    required String platform,
  }) async {
    final url = '$baseUrl/api/notifications/register-token';
    final payload = {
      'device_token': token,
      'platform': platform,
    };

    final resp = await apiClient.post(
      url,
      body: jsonEncode(payload),
      headers: {'Content-Type': 'application/json'},
    );

    if (resp.statusCode >= 400) {
      if (kDebugMode) {
        debugPrint('[NotificationsApi] registerToken error: '
            '${resp.statusCode} ${resp.body}');
      }
      throw Exception('No se pudo registrar el token del dispositivo');
    }
  }

  /// Elimina el token del backend (útil en logout o desinstalaciones).
  Future<void> deleteToken({
    required String token,
  }) async {
    final url = '$baseUrl/api/notifications/delete-token';
    final payload = {'device_token': token};

    final resp = await apiClient.post(
      url,
      body: jsonEncode(payload),
      headers: {'Content-Type': 'application/json'},
    );

    if (resp.statusCode >= 400) {
      if (kDebugMode) {
        debugPrint('[NotificationsApi] deleteToken error: '
            '${resp.statusCode} ${resp.body}');
      }
      throw Exception('No se pudo eliminar el token del dispositivo');
    }
  }

  /// (Opcional, solo para dev) Envía una notificación de prueba a ESTE dispositivo.
  /// El backend debe implementar el endpoint para enviar a device_token.
  Future<void> sendTestToToken({
    required String token,
    String? title,
    String? body,
    Map<String, dynamic>? data,
  }) async {
    final url = '$baseUrl/api/notifications/send-test';
    final payload = {
      'device_token': token,
      if (title != null) 'title': title,
      if (body != null) 'body': body,
      if (data != null) 'data': data,
    };

    final resp = await apiClient.post(
      url,
      body: jsonEncode(payload),
      headers: {'Content-Type': 'application/json'},
    );

    if (resp.statusCode >= 400) {
      if (kDebugMode) {
        debugPrint('[NotificationsApi] sendTestToToken error: '
            '${resp.statusCode} ${resp.body}');
      }
      throw Exception('No se pudo enviar la notificación de prueba');
    }
  }
}
