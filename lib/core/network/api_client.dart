// lib/core/network/api_client.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:base_app/data/session/session_manager.dart';
import 'package:base_app/core/services/app_logger.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Cliente HTTP centralizado con:
/// - Inyección automática del access token (Bearer)
/// - Reintento 1 sola vez si hay 401 (usa refresh token)
/// - Actualización del access token en SessionManager
class ApiClient {
  final String baseUrl;
  final SessionManager session;
  final http.Client _client;

  ApiClient({
    required this.baseUrl,
    required this.session,
    http.Client? client,
  }) : _client = client ?? http.Client();

  /// ---- Métodos convenientes (JSON) ----

  Future<http.Response> get(
    String path, {
    Map<String, String>? headers,
    bool auth = true,
  }) {
    return _sendWithAuth(
      method: 'GET',
      uri: _uri(path),
      headers: headers,
      auth: auth,
    );
  }

  Future<http.Response> post(
    String path, {
    Map<String, String>? headers,
    Object? body,
    bool json = true,
    bool auth = true,
  }) {
    return _sendWithAuth(
      method: 'POST',
      uri: _uri(path),
      headers: headers,
      body: body,
      json: json,
      auth: auth,
    );
  }

  Future<http.Response> put(
    String path, {
    Map<String, String>? headers,
    Object? body,
    bool json = true,
    bool auth = true,
  }) {
    return _sendWithAuth(
      method: 'PUT',
      uri: _uri(path),
      headers: headers,
      body: body,
      json: json,
      auth: auth,
    );
  }

  Future<http.Response> delete(
    String path, {
    Map<String, String>? headers,
    Object? body,
    bool json = true,
    bool auth = true,
  }) {
    return _sendWithAuth(
      method: 'DELETE',
      uri: _uri(path),
      headers: headers,
      body: body,
      json: json,
      auth: auth,
    );
  }

  /// ---- Núcleo de envío con retry por refresh ----

  Future<http.Response> _sendWithAuth({
    required String method,
    required Uri uri,
    Map<String, String>? headers,
    Object? body,
    bool json = true,
    bool auth = true,
  }) async {
    // Construye headers base
    final h = <String, String>{
      if (json) 'Content-Type': 'application/json',
      'Accept': 'application/json',
      ...?headers,
    };

    // Inserta el access token si corresponde
    String? access;
    if (auth) {
      access = await session.getToken();
      if (access != null && access.isNotEmpty) {
        h['Authorization'] = 'Bearer $access';
      }
    }

    // Función para ejecutar la request
    Future<http.Response> run() {
      switch (method) {
        case 'GET':
          return _client.get(uri, headers: h);
        case 'POST':
          return _client.post(uri, headers: h, body: _encodeBody(body, json));
        case 'PUT':
          return _client.put(uri, headers: h, body: _encodeBody(body, json));
        case 'DELETE':
          return _client.delete(uri, headers: h, body: _encodeBody(body, json));
        default:
          throw UnsupportedError('HTTP method no soportado: $method');
      }
    }

    http.Response res;
    try {
      if (kDebugMode) {
        appLogger.d({'event': 'api_req', 'm': method, 'url': uri.toString()});
      }
      res = await run().timeout(const Duration(seconds: 20));
    } on SocketException {
      rethrow;
    } on TimeoutException {
      rethrow;
    }

    // Si NO requiere auth o no es 401 -> devolver tal cual
    if (!auth || res.statusCode != 401) return res;

    // --------- 401: intentamos refresh UNA sola vez ---------
    final refreshed = await _tryRefreshAccessToken();
    if (!refreshed) {
      return res; // sigue 401: que el caller maneje logout/redirección
    }

    // Con nuevo access, rehacemos headers Authorization y reintentamos
    final newAccess = await session.getToken();
    if (newAccess != null && newAccess.isNotEmpty) {
      h['Authorization'] = 'Bearer $newAccess';
    } else {
      h.remove('Authorization');
    }

    try {
      if (kDebugMode) {
        appLogger.d({
          'event': 'api_retry_after_refresh',
          'm': method,
          'url': uri.toString()
        });
      }
      res = await run().timeout(const Duration(seconds: 20));
      return res;
    } on SocketException {
      rethrow;
    } on TimeoutException {
      rethrow;
    }
  }

  /// Llama al backend /api/auth/refresh enviando el refresh token como Bearer.
  /// Si obtiene access_token, lo guarda en SessionManager.
  Future<bool> _tryRefreshAccessToken() async {
    try {
      final refresh = await session.getRefreshToken();
      if (refresh == null || refresh.isEmpty) {
        if (kDebugMode) {
          appLogger.w({'event': 'refresh_skip', 'reason': 'no_refresh_token'});
        }
        return false;
      }

      final uri = _uri('/api/auth/refresh');
      final res = await _client
          .post(
            uri,
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
              'Authorization': 'Bearer $refresh',
            },
          )
          .timeout(const Duration(seconds: 15));

      if (kDebugMode) {
        appLogger.d({
          'event': 'refresh_res',
          'status': res.statusCode,
          'body': res.body
        });
      }

      if (res.statusCode < 200 || res.statusCode >= 300) {
        return false;
      }

      dynamic body;
      try {
        body = jsonDecode(res.body.isEmpty ? '{}' : res.body);
      } catch (_) {
        body = {};
      }

      final newAccess = (body['access_token'] ??
              body['token'] ??
              body['jwt'] ??
              body['accessToken'])
          ?.toString();

      if (newAccess == null || newAccess.isEmpty) {
        return false;
      }

      await session.updateAccessToken(newAccess);
      return true;
    } catch (e, st) {
      if (kDebugMode) {
        appLogger.e({
          'event': 'refresh_error',
          'err': e.toString(),
          'stack': st.toString()
        });
      }
      return false;
    }
  }

  Uri _uri(String path) {
    // Permite pasar path ya absoluto para casos especiales
    if (path.startsWith('http://') || path.startsWith('https://')) {
      return Uri.parse(path);
    }
    // Asegura una sola barra
    final base = baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;
    final p = path.startsWith('/') ? path : '/$path';
    return Uri.parse('$base$p');
  }

  Object? _encodeBody(Object? body, bool json) {
    if (!json || body == null) return body;
    if (body is String) return body; // ya viene jsonEncodeado
    return jsonEncode(body);
  }

  void close() => _client.close();
}
