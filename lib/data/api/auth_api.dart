import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:base_app/core/services/app_logger.dart';

class AuthApi {
  final String baseUrl;
  final http.Client _client;

  AuthApi({required this.baseUrl, http.Client? client})
      : _client = client ?? http.Client();

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
            headers: const {'Content-Type': 'application/json'},
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

      final body = jsonDecode(res.body.isEmpty ? '{}' : res.body);

      if (res.statusCode >= 200 && res.statusCode < 300) {
        return body as Map<String, dynamic>;
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
    final uri = Uri.parse('$baseUrl/api/auth/me');

    try {
      appLogger.i({'event': 'me_request', 'url': uri.toString()});

      final res = await _client
          .get(
            uri,
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
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
        return body as Map<String, dynamic>;
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
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({
              'reset_token': resetToken,
              'new_password': newPassword,
            }),
          )
          .timeout(const Duration(seconds: 10));

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

      final body = jsonDecode(res.body.isEmpty ? '{}' : res.body);
      if (res.statusCode >= 200 && res.statusCode < 300) {
        return;
      } else {
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

  // --- Logout ---
  Future<void> logout({required String token}) async {
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

      // Silencioso: la app limpia sesión local aunque falle
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

  /// Paso 1 (por EMAIL): solicitar envío de código
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
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({'email': email}),
          )
          .timeout(const Duration(seconds: 10));

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
        'event': 'pwd_reset_request_email_unhandled',
        'error': e.toString(),
        'stack': st.toString(),
      });
      throw AuthException('Error inesperado solicitando el código');
    }
  }

  /// Paso 2 (por EMAIL): verificar código y obtener reset_token
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
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({'email': email, 'code': code}),
          )
          .timeout(const Duration(seconds: 10));

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
        'event': 'pwd_reset_verify_email_unhandled',
        'error': e.toString(),
        'stack': st.toString(),
      });
      throw AuthException('Error inesperado verificando el código');
    }
  }
}

class AuthException implements Exception {
  final String message;
  final int? statusCode;
  AuthException(this.message, {this.statusCode});

  @override
  String toString() => 'AuthException(${statusCode ?? '-' }): $message';
}
