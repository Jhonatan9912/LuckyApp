import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:base_app/core/services/app_logger.dart';
import 'package:base_app/core/network/api_client.dart';

class AuthApi {
  final String baseUrl;
  final http.Client _client;
  final ApiClient?
  _apiClient; // ← opcional: si lo pasas, usaremos ApiClient para /me y /logout

  AuthApi({required this.baseUrl, http.Client? client, ApiClient? apiClient})
    : _client = client ?? http.Client(),
      _apiClient = apiClient;

  Future<Map<String, dynamic>> loginWithPhone({
    required String phone,
    required String password,
  }) async {
    final uri = Uri.parse('$baseUrl/api/auth/login');
    final maskedPhone = phone.isNotEmpty
        ? '${phone.substring(0, phone.length > 4 ? phone.length - 4 : phone.length)}****'
        : '';

    try {
      appLogger.i({
        'event': 'login_request',
        'url': uri.toString(),
        'phone': maskedPhone,
      });

      final res = await _client
          .post(
            uri,
            headers: const {
              'Content-Type': 'application/json',
              'Accept': 'application/json', // 👈 asegura JSON real
            },
            body: jsonEncode({'phone': phone, 'password': password}),
          )
          .timeout(const Duration(seconds: 10));

      if (kDebugMode) {
        appLogger.d({
          'event': 'login_response',
          'status': res.statusCode,
          'body': res.body,
        });
      } else {
        appLogger.d({'event': 'login_response', 'status': res.statusCode});
      }

      // 👇 Decodificación robusta: intenta doble decode si viene stringificado
      dynamic body;
      try {
        body = jsonDecode(res.body.isEmpty ? '{}' : res.body);
        if (body is String) body = jsonDecode(body);
      } catch (_) {
        final cleaned = res.body.trim();
        body = jsonDecode(cleaned.isEmpty ? '{}' : cleaned);
        if (body is String) body = jsonDecode(body);
      }

      if (res.statusCode >= 200 && res.statusCode < 300) {
        if (body is! Map) {
          throw const FormatException('Payload inesperado (no es objeto JSON)');
        }
        return Map<String, dynamic>.from(body);
      } else {
        final msg = (body is Map && body['error'] != null)
            ? body['error'].toString()
            : 'Error de autenticación';
        throw AuthException(msg, statusCode: res.statusCode);
      }
    } on SocketException {
      throw AuthException('No hay conexión con el servidor');
    } on TimeoutException {
      throw AuthException('Tiempo de espera agotado');
    } on FormatException {
      throw AuthException('Respuesta inválida del servidor');
    } on AuthException {
      rethrow;
    } catch (e, st) {
      appLogger.e({
        'event': 'login_unhandled',
        'error': e.toString(),
        'stack': st.toString(),
      });
      throw AuthException('Error inesperado al iniciar sesión');
    }
  }

  Future<Map<String, dynamic>> me(String token) async {
   // Si tenemos ApiClient, lo usamos CON auto-refresh (auth:true).
    if (_apiClient != null) {
      const path = '/api/auth/me';

      // 👉 Enviamos Authorization manual SOLO si tenemos access.
      final headers = <String, String>{
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      };
      try {
        appLogger.i({'event': 'me_request', 'url': '$baseUrl$path'});

        final res = await _apiClient
            .get(
              path,
              headers: headers,
              auth: true,
            )
            .timeout(const Duration(seconds: 10));

        if (kDebugMode) {
          appLogger.d({
            'event': 'me_response',
            'status': res.statusCode,
            'body': res.body,
          });
        } else {
          appLogger.d({'event': 'me_response', 'status': res.statusCode});
        }

        final body = jsonDecode(res.body.isEmpty ? '{}' : res.body);
        if (res.statusCode >= 200 && res.statusCode < 300) {
          return Map<String, dynamic>.from(body);
        } else {
          final msg = (body is Map && body['error'] != null)
              ? body['error'].toString()
              : 'Token inválido o expirado';
          throw AuthException(msg, statusCode: res.statusCode);
        }
      } on SocketException {
        throw AuthException('No hay conexión con el servidor');
      } on TimeoutException {
        throw AuthException('Tiempo de espera agotado');
      } on FormatException {
        throw AuthException('Respuesta inválida del servidor');
      } on AuthException {
        rethrow;
      } catch (e, st) {
        appLogger.e({
          'event': 'me_unhandled',
          'error': e.toString(),
          'stack': st.toString(),
        });
        throw AuthException('Error inesperado al validar sesión');
      }
    }

    // Fallback: http.Client con Authorization manual (sin auto-refresh).
    final uri = Uri.parse('$baseUrl/api/auth/me');
    try {
      appLogger.i({'event': 'me_request', 'url': uri.toString()});

      final res = await _client
          .get(
            uri,
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
              if (token.isNotEmpty) 'Authorization': 'Bearer $token',
            },
          )
          .timeout(const Duration(seconds: 10));

      if (kDebugMode) {
        appLogger.d({
          'event': 'me_response',
          'status': res.statusCode,
          'body': res.body,
        });
      } else {
        appLogger.d({'event': 'me_response', 'status': res.statusCode});
      }

      final body = jsonDecode(res.body.isEmpty ? '{}' : res.body);
      if (res.statusCode >= 200 && res.statusCode < 300) {
        return Map<String, dynamic>.from(body);
      } else {
        final msg = (body is Map && body['error'] != null)
            ? body['error'].toString()
            : 'Token inválido o expirado';
        throw AuthException(msg, statusCode: res.statusCode);
      }
    } on SocketException {
      throw AuthException('No hay conexión con el servidor');
    } on TimeoutException {
      throw AuthException('Tiempo de espera agotado');
    } on FormatException {
      throw AuthException('Respuesta inválida del servidor');
    } on AuthException {
      rethrow;
    } catch (e, st) {
      appLogger.e({
        'event': 'me_unhandled',
        'error': e.toString(),
        'stack': st.toString(),
      });
      throw AuthException('Error inesperado al validar sesión');
    }
  }

  // === RESET DE CONTRASEÑA === (por TELÉFONO; deja o elimina según tu app)

  Future<void> requestPasswordReset({required String phone}) async {
    final uri = Uri.parse('$baseUrl/api/reset/request');

    try {
      final masked = phone.isNotEmpty
          ? '${phone.substring(0, phone.length > 4 ? phone.length - 4 : phone.length)}****'
          : '';
      appLogger.i({
        'event': 'pwd_reset_request',
        'url': uri.toString(),
        'phone': masked,
      });

      final res = await _client
          .post(
            uri,
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({'phone': phone}),
          )
          .timeout(const Duration(seconds: 10));

      if (kDebugMode) {
        appLogger.d({
          'event': 'pwd_reset_request_res',
          'status': res.statusCode,
          'body': res.body,
        });
      } else {
        appLogger.d({
          'event': 'pwd_reset_request_res',
          'status': res.statusCode,
        });
      }

      final body = jsonDecode(res.body.isEmpty ? '{}' : res.body);
      if (res.statusCode >= 200 && res.statusCode < 300) {
        return;
      } else {
        final msg = (body is Map && body['error'] != null)
            ? body['error'].toString()
            : 'No se pudo enviar el código';
        throw AuthException(msg, statusCode: res.statusCode);
      }
    } on SocketException {
      throw AuthException('No hay conexión con el servidor');
    } on TimeoutException {
      throw AuthException('Tiempo de espera agotado');
    } on FormatException {
      throw AuthException('Respuesta inválida del servidor');
    } on AuthException {
      rethrow;
    } catch (e, st) {
      appLogger.e({
        'event': 'pwd_reset_request_unhandled',
        'error': e.toString(),
        'stack': st.toString(),
      });
      throw AuthException('Error inesperado solicitando el código');
    }
  }

  Future<String> verifyResetCode({
    required String phone,
    required String code,
  }) async {
    final uri = Uri.parse('$baseUrl/api/reset/verify');

    try {
      final masked = phone.isNotEmpty
          ? '${phone.substring(0, phone.length > 4 ? phone.length - 4 : phone.length)}****'
          : '';
      appLogger.i({
        'event': 'pwd_reset_verify',
        'url': uri.toString(),
        'phone': masked,
      });

      final res = await _client
          .post(
            uri,
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({'phone': phone, 'code': code}),
          )
          .timeout(const Duration(seconds: 10));

      if (kDebugMode) {
        appLogger.d({
          'event': 'pwd_reset_verify_res',
          'status': res.statusCode,
          'body': res.body,
        });
      } else {
        appLogger.d({
          'event': 'pwd_reset_verify_res',
          'status': res.statusCode,
        });
      }

      final body = jsonDecode(res.body.isEmpty ? '{}' : res.body);
      if (res.statusCode >= 200 && res.statusCode < 300) {
        final token = (body is Map ? body['reset_token'] : null)?.toString();
        if (token == null || token.isEmpty) {
          throw AuthException('Token de restablecimiento no recibido');
        }
        return token;
      } else {
        final msg = (body is Map && body['error'] != null)
            ? body['error'].toString()
            : 'Código inválido';
        throw AuthException(msg, statusCode: res.statusCode);
      }
    } on SocketException {
      throw AuthException('No hay conexión con el servidor');
    } on TimeoutException {
      throw AuthException('Tiempo de espera agotado');
    } on FormatException {
      throw AuthException('Respuesta inválida del servidor');
    } on AuthException {
      rethrow;
    } catch (e, st) {
      appLogger.e({
        'event': 'pwd_reset_verify_unhandled',
        'error': e.toString(),
        'stack': st.toString(),
      });
      throw AuthException('Error inesperado verificando el código');
    }
  }

  // --- Logout ---
  Future<void> logout({required String token}) async {
    // Si hay ApiClient, úsalo para enviar el ACCESS actual (él lo inyecta).
    if (_apiClient != null) {
      const path = '/api/auth/logout';
      try {
        appLogger.i({'event': 'logout_request', 'url': '$baseUrl$path'});

        await _apiClient
            .post(
              path,
              headers: const {'Content-Type': 'application/json'},
              json: true,
              auth: true, // ← ApiClient añade Authorization
            )
            .timeout(const Duration(seconds: 10));
      } catch (e, st) {
        appLogger.e({
          'event': 'logout_unhandled',
          'error': e.toString(),
          'stack': st.toString(),
        });
      }
      return;
    }

    // Fallback retrocompatible: http.Client con Authorization manual.
    final uri = Uri.parse('$baseUrl/api/auth/logout');
    try {
      appLogger.i({'event': 'logout_request', 'url': uri.toString()});

      await _client
          .post(
            uri,
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
          )
          .timeout(const Duration(seconds: 10));
    } catch (e, st) {
      appLogger.e({
        'event': 'logout_unhandled',
        'error': e.toString(),
        'stack': st.toString(),
      });
    }
  }

  void close() => _client.close();

  // ====== RESET POR EMAIL ======

  // Helper para logs: enmascara correo (j***@dominio.com)
  String _maskEmail(String email) {
    final at = email.indexOf('@');
    if (at <= 1) return '****';
    final name = email.substring(0, at);
    final domain = email.substring(at);
    final visible = name.substring(0, 1);
    return '$visible****$domain';
  }

  // === RESET POR EMAIL ===

  /// Paso 1: solicitar envío de código (EMAIL)
  Future<void> requestPasswordResetByEmail({required String email}) async {
    final uri = Uri.parse('$baseUrl/api/reset/request');

    try {
      final masked = _maskEmail(email);
      appLogger.i({
        'event': 'pwd_reset_request_email',
        'url': uri.toString(),
        'email': masked,
      });

      final res = await _client
          .post(
            uri,
            headers: const {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: jsonEncode({'email': email}),
          )
          // ⬇️ da un poco más de aire
          .timeout(const Duration(seconds: 25));

      if (kDebugMode) {
        appLogger.d({
          'event': 'pwd_reset_request_email_res',
          'status': res.statusCode,
          'body': res.body,
        });
      } else {
        appLogger.d({
          'event': 'pwd_reset_request_email_res',
          'status': res.statusCode,
        });
      }

      // éxito si 200 ó 202
      if (res.statusCode == 200 || res.statusCode == 202) return;

      // intenta leer error del backend
      dynamic body;
      try {
        body = jsonDecode(res.body.isEmpty ? '{}' : res.body);
      } catch (_) {
        body = {};
      }
      final msg = (body is Map && body['error'] != null)
          ? body['error'].toString()
          : 'No se pudo enviar el código';
      throw AuthException(msg, statusCode: res.statusCode);
    } on SocketException {
      throw AuthException('No hay conexión con el servidor');
    } on TimeoutException {
      throw AuthException('Tiempo de espera agotado');
    } on FormatException {
      throw AuthException('Respuesta inválida del servidor');
    } on AuthException {
      rethrow;
    } catch (e, st) {
      appLogger.e({
        'event': 'pwd_reset_request_email_unhandled',
        'error': e.toString(),
        'stack': st.toString(),
      });
      throw AuthException('Error inesperado solicitando el código');
    }
  }

  /// Paso 2: verificar código (EMAIL) y obtener reset_token
  Future<String> verifyResetCodeByEmail({
    required String email,
    required String code,
  }) async {
    final uri = Uri.parse('$baseUrl/api/reset/verify');

    try {
      final masked = _maskEmail(email);
      appLogger.i({
        'event': 'pwd_reset_verify_email',
        'url': uri.toString(),
        'email': masked,
      });

      final res = await _client
          .post(
            uri,
            headers: const {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: jsonEncode({'email': email, 'code': code}),
          )
          .timeout(const Duration(seconds: 25));

      if (kDebugMode) {
        appLogger.d({
          'event': 'pwd_reset_verify_email_res',
          'status': res.statusCode,
          'body': res.body,
        });
      } else {
        appLogger.d({
          'event': 'pwd_reset_verify_email_res',
          'status': res.statusCode,
        });
      }

      if (res.statusCode < 200 || res.statusCode >= 300) {
        dynamic body;
        try {
          body = jsonDecode(res.body.isEmpty ? '{}' : res.body);
        } catch (_) {
          body = {};
        }
        final msg = (body is Map && body['error'] != null)
            ? body['error'].toString()
            : 'Código inválido';
        throw AuthException(msg, statusCode: res.statusCode);
      }

      // acepta snake_case o camelCase
      final data = jsonDecode(res.body.isEmpty ? '{}' : res.body);
      final token = (data['reset_token'] ?? data['resetToken'])?.toString();
      if (token == null || token.isEmpty) {
        throw AuthException('Token de restablecimiento no recibido');
      }
      return token;
    } on SocketException {
      throw AuthException('No hay conexión con el servidor');
    } on TimeoutException {
      throw AuthException('Tiempo de espera agotado');
    } on FormatException {
      throw AuthException('Respuesta inválida del servidor');
    } on AuthException {
      rethrow;
    } catch (e, st) {
      appLogger.e({
        'event': 'pwd_reset_verify_email_unhandled',
        'error': e.toString(),
        'stack': st.toString(),
      });
      throw AuthException('Error inesperado verificando el código');
    }
  }

  /// Paso 3: confirmar nueva contraseña (EMAIL)
  Future<void> confirmPasswordReset({
    required String resetToken,
    required String newPassword,
  }) async {
    final uri = Uri.parse('$baseUrl/api/reset/confirm');

    try {
      appLogger.i({'event': 'pwd_reset_confirm', 'url': uri.toString()});

      final res = await _client
          .post(
            uri,
            headers: const {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: jsonEncode({
              // backend original espera snake_case
              'reset_token': resetToken,
              'new_password': newPassword,
            }),
          )
          .timeout(const Duration(seconds: 25));

      if (kDebugMode) {
        appLogger.d({
          'event': 'pwd_reset_confirm_res',
          'status': res.statusCode,
          'body': res.body,
        });
      } else {
        appLogger.d({
          'event': 'pwd_reset_confirm_res',
          'status': res.statusCode,
        });
      }

      if (res.statusCode < 200 || res.statusCode >= 300) {
        dynamic body;
        try {
          body = jsonDecode(res.body.isEmpty ? '{}' : res.body);
        } catch (_) {
          body = {};
        }
        final msg = (body is Map && body['error'] != null)
            ? body['error'].toString()
            : 'No se pudo actualizar la contraseña';
        throw AuthException(msg, statusCode: res.statusCode);
      }
    } on SocketException {
      throw AuthException('No hay conexión con el servidor');
    } on TimeoutException {
      throw AuthException('Tiempo de espera agotado');
    } on FormatException {
      throw AuthException('Respuesta inválida del servidor');
    } on AuthException {
      rethrow;
    } catch (e, st) {
      appLogger.e({
        'event': 'pwd_reset_confirm_unhandled',
        'error': e.toString(),
        'stack': st.toString(),
      });
      throw AuthException('Error inesperado al actualizar la contraseña');
    }
  }

  /// Intercambia un refresh token (largo) por un nuevo access token (corto).
  Future<Map<String, dynamic>> refresh(String refreshToken) async {
    final uri = Uri.parse('$baseUrl/api/auth/refresh');

    try {
      appLogger.i({'event': 'refresh_request', 'url': uri.toString()});

      final res = await _client
          .post(
            uri,
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
              // IMPORTANTE: el refresh se envía como Bearer igual que un access
              'Authorization': 'Bearer $refreshToken',
            },
          )
          .timeout(const Duration(seconds: 10));

      if (kDebugMode) {
        appLogger.d({
          'event': 'refresh_response',
          'status': res.statusCode,
          'body': res.body,
        });
      } else {
        appLogger.d({'event': 'refresh_response', 'status': res.statusCode});
      }

      dynamic body;
      try {
        body = jsonDecode(res.body.isEmpty ? '{}' : res.body);
      } catch (_) {
        body = {};
      }

      if (res.statusCode >= 200 && res.statusCode < 300) {
        if (body is! Map) {
          throw const FormatException('Payload inesperado en /refresh');
        }
        // Backend devuelve: { ok: true, access_token: '...' }
        return Map<String, dynamic>.from(body);
      } else {
        final msg = (body is Map && body['error'] != null)
            ? body['error'].toString()
            : 'No se pudo refrescar la sesión';
        throw AuthException(msg, statusCode: res.statusCode);
      }
    } on SocketException {
      throw AuthException('No hay conexión con el servidor');
    } on TimeoutException {
      throw AuthException('Tiempo de espera agotado');
    } on FormatException {
      throw AuthException('Respuesta inválida del servidor');
    } on AuthException {
      rethrow;
    } catch (e, st) {
      appLogger.e({
        'event': 'refresh_unhandled',
        'error': e.toString(),
        'stack': st.toString(),
      });
      throw AuthException('Error inesperado al refrescar sesión');
    }
  }

  /// (Opcional) Revoca el refresh token actual en el backend.
  Future<void> logoutRefresh({required String refreshToken}) async {
    final uri = Uri.parse('$baseUrl/api/auth/logout/refresh');

    try {
      appLogger.i({'event': 'logout_refresh_request', 'url': uri.toString()});

      await _client
          .post(
            uri,
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $refreshToken',
            },
          )
          .timeout(const Duration(seconds: 10));
    } catch (e, st) {
      appLogger.e({
        'event': 'logout_refresh_unhandled',
        'error': e.toString(),
        'stack': st.toString(),
      });
      // Silencioso: aunque falle, la app puede borrar localmente el refresh
    }
  }
}

class AuthException implements Exception {
  final String message;
  final int? statusCode;
  AuthException(this.message, {this.statusCode});

  @override
  String toString() => 'AuthException(${statusCode ?? '-'}): $message';
}
