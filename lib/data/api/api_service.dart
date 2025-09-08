// lib/data/api/api_service.dart
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:base_app/core/config/env.dart';
import 'package:base_app/data/session/session_manager.dart';
import 'package:base_app/domain/models/user.dart';

class ApiException implements Exception {
  final int statusCode;
  final String body;
  ApiException(this.statusCode, this.body);

  String get message {
    try {
      final decoded = json.decode(body);
      if (decoded is Map<String, dynamic>) {
        return (decoded['error']?.toString() ??
            decoded['message']?.toString() ??
            body);
      }
      return body;
    } catch (_) {
      return body;
    }
  }

  @override
  String toString() => 'ApiException($statusCode): $body';
}

class ApiService {
  /// URL base por defecto (desde Env) accesible de forma estática.
  static String get defaultBaseUrl => Env.apiBaseUrl;

  final String baseUrl;
  ApiService({String? baseUrl}) : baseUrl = baseUrl ?? Env.apiBaseUrl;

  Future<Map<String, String>> _headers() async {
    final token = await SessionManager().getToken();
    return {
      'Content-Type': 'application/json',
      if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
    };
  }

  /// Headers SOLO con Authorization (útil para Image.network, descargas, etc.)
  static Future<Map<String, String>> authHeaders() async {
    final token = await SessionManager().getToken();
    return {
      if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
    };
  }

  Uri _uri(String path) {
    if (path.startsWith('http://') || path.startsWith('https://')) {
      return Uri.parse(path);
    }
    final normalized = path.startsWith('/') ? path : '/$path';
    return Uri.parse('$baseUrl$normalized');
  }

  Future<dynamic> get(String path) async {
    final res = await http
        .get(_uri(path), headers: await _headers())
        .timeout(const Duration(seconds: 20));
    return _handle(res);
  }

  Future<dynamic> post(String path, {Object? body}) async {
    final res = await http
        .post(
          _uri(path),
          headers: await _headers(),
          body: body is String ? body : json.encode(body),
        )
        .timeout(const Duration(seconds: 20));
    return _handle(res);
  }

  Future<dynamic> put(String path, {Object? body}) async {
    final res = await http
        .put(
          _uri(path),
          headers: await _headers(),
          body: body is String ? body : json.encode(body),
        )
        .timeout(const Duration(seconds: 20));
    return _handle(res);
  }

  Future<dynamic> delete(String path) async {
    final res = await http
        .delete(_uri(path), headers: await _headers())
        .timeout(const Duration(seconds: 20));
    return _handle(res);
  }

  dynamic _handle(http.Response res) {
    final ok = res.statusCode >= 200 && res.statusCode < 300;
    final body = res.body.isEmpty ? '{}' : res.body;
    if (!ok) throw ApiException(res.statusCode, body);
    try {
      return json.decode(body);
    } catch (_) {
      // Por si el endpoint devuelve texto plano
      return body;
    }
  }

  // =======================
  // Helpers específicos
  // =======================

  Future<List<Map<String, dynamic>>> fetchIdentificationTypes() async {
    dynamic res;
    try {
      res = await get('/identification-types');
    } on ApiException catch (e) {
      if (e.statusCode == 404) {
        res = await get('/api/identification-types');
      } else {
        rethrow;
      }
    }

    if (res is List) {
      return List<Map<String, dynamic>>.from(res);
    }
    if (res is Map<String, dynamic> && res['data'] is List) {
      return List<Map<String, dynamic>>.from(res['data'] as List);
    }
    throw ApiException(500, 'Formato inesperado en identification-types');
  }

  Future<bool> registerUser(User user) async {
    final paths = <String>['/register', '/api/auth/register'];
    ApiException? lastError;

    for (final p in paths) {
      try {
        await post(p, body: user.toJson());
        return true;
      } on ApiException catch (e) {
        if (e.statusCode == 404) {
          lastError = e;
          continue;
        }
        rethrow;
      }
    }

    throw lastError ?? ApiException(404, 'Endpoint de registro no encontrado');
  }
}
