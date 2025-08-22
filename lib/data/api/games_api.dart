import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import 'dart:async';
import 'dart:io';

class GamesApi {
  final String baseUrl;
  final http.Client _client;

  GamesApi({required this.baseUrl, http.Client? client})
    : _client = client ?? http.Client();

  Map<String, String> _headers({String? token, int? xUserId}) {
    final h = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };
    if (token != null && token.isNotEmpty) {
      h['Authorization'] = 'Bearer $token';
    }
    if (xUserId != null) {
      // permite forzar el mismo user que reservó antes
      h['X-USER-ID'] = xUserId.toString();
    }
    return h;
  }

  void _log(
    String tag,
    Uri uri,
    Map<String, String> headers, [
    Object? body,
    int? status,
    String? resp,
  ]) {
    if (!kDebugMode) return;
    debugPrint('[$tag] ${uri.toString()}');
    debugPrint('[$tag] headers=$headers');
    if (body != null) debugPrint('[$tag] body=$body');
    if (status != null) debugPrint('[$tag] status=$status');
    if (resp != null) debugPrint('[$tag] resp=$resp');
  }

  Map<String, dynamic> _ok(http.Response r, Map<String, dynamic>? parsed) => {
    'ok': true,
    'status': r.statusCode,
    'code': parsed?['code'],
    'message': parsed?['message'],
    'data': parsed,
  };

  Map<String, dynamic> _fail({
    required int? status,
    String? code,
    String? message,
    Map<String, dynamic>? data,
  }) => {
    'ok': false,
    'status': status,
    'code': code,
    'message': message,
    'data': data,
  };

  // ======================
  // GENERATE (normalizado)
  // ======================
  Future<Map<String, dynamic>> generate({String? token, int? xUserId}) async {
    final uri = Uri.parse('$baseUrl/api/games/generate');
    final headers = _headers(token: token, xUserId: xUserId);

    _log('GENERATE-REQ', uri, headers);
    http.Response res;
    try {
      res = await _client
          .post(uri, headers: headers)
          .timeout(const Duration(seconds: 10));
    } catch (e) {
      return _fail(
        status: null,
        code: 'NETWORK_ERROR',
        message: 'No se pudo conectar con el servidor ($e)',
      );
    }
    _log('GENERATE-RES', uri, headers, null, res.statusCode, res.body);

    Map<String, dynamic>? parsed;
    try {
      parsed = res.body.isEmpty ? null : jsonDecode(res.body);
    } catch (_) {
      parsed = null;
    }

    if (res.statusCode >= 200 && res.statusCode < 300) {
      // 🔧 Normaliza como en generate(): si viene { ok, data }, toma el "data" interno
      Map<String, dynamic>? core;
      if (parsed is Map<String, dynamic>) {
        final maybeInner = parsed['data'];
        core = (maybeInner is Map<String, dynamic>) ? maybeInner : parsed;
      }
      return {'ok': true, 'status': res.statusCode, 'data': core};
    }

    return _fail(
      status: res.statusCode,
      code: parsed?['code']?.toString() ?? 'HTTP_${res.statusCode}',
      message:
          parsed?['message']?.toString() ??
          'Error generando números (HTTP ${res.statusCode})',
      data: parsed,
    );
  }

  // ======================
  // COMMIT (ruta correcta + enteros)
  // ======================
  Future<Map<String, dynamic>> commit({
    required int gameId,
    required List<int> numbers,
    String? token,
    int? xUserId, // ← reemplaza userIdForDev por xUserId
  }) async {
    // Backend: POST /api/games/commit
    final uri = Uri.parse('$baseUrl/api/games/commit');

    // Enviar ENTEROS, no strings
    final payload = jsonEncode({
      'game_id': gameId,
      'numbers': numbers,
      // No mandes 'user_id' en body; el backend toma el uid del token o X-USER-ID
    });

    // Usa el helper con xUserId
    final headers = _headers(token: token, xUserId: xUserId);

    _log('COMMIT-REQ', uri, headers, payload);
    http.Response res;
    try {
      res = await _client
          .post(uri, headers: headers, body: payload)
          .timeout(const Duration(seconds: 10));
    } catch (e) {
      return _fail(
        status: null,
        code: 'NETWORK_ERROR',
        message: 'No se pudo conectar con el servidor ($e)',
      );
    }
    _log('COMMIT-RES', uri, headers, null, res.statusCode, res.body);

    Map<String, dynamic>? parsed;
    try {
      parsed = res.body.isEmpty ? null : jsonDecode(res.body);
    } catch (_) {
      parsed = null;
    }

    if (res.statusCode >= 200 && res.statusCode < 300) {
      return _ok(res, parsed);
    }

    if (res.statusCode == 409) {
      return _fail(
        status: 409,
        code: (parsed?['code'] ?? 'CONFLICT').toString(),
        message: (parsed?['message'] ?? 'Conflicto al guardar selección')
            .toString(),
        data: parsed,
      );
    }

    // Fallback con X-USER-ID si 401
    if (res.statusCode == 401 && xUserId != null) {
      final devHeaders = {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        'X-USER-ID': xUserId.toString(),
      };
      _log('COMMIT-REQ(DEV)', uri, devHeaders, payload);
      try {
        final devRes = await _client
            .post(uri, headers: devHeaders, body: payload)
            .timeout(const Duration(seconds: 10));
        _log(
          'COMMIT-RES(DEV)',
          uri,
          devHeaders,
          null,
          devRes.statusCode,
          devRes.body,
        );

        Map<String, dynamic>? devParsed;
        try {
          devParsed = devRes.body.isEmpty ? null : jsonDecode(devRes.body);
        } catch (_) {
          devParsed = null;
        }

        if (devRes.statusCode >= 200 && devRes.statusCode < 300) {
          return _ok(devRes, devParsed);
        }

        return _fail(
          status: devRes.statusCode,
          code: (devParsed?['code'] ?? 'HTTP_${devRes.statusCode}').toString(),
          message:
              (devParsed?['message'] ??
                      'Error HTTP ${devRes.statusCode} al guardar selección')
                  .toString(),
          data: devParsed,
        );
      } catch (e) {
        return _fail(
          status: null,
          code: 'NETWORK_ERROR',
          message: 'No se pudo conectar con el servidor ($e)',
        );
      }
    }

    return _fail(
      status: res.statusCode,
      code: (parsed?['code'] ?? 'HTTP_${res.statusCode}').toString(),
      message:
          (parsed?['message'] ??
                  'Error HTTP ${res.statusCode} al guardar selección')
              .toString(),
      data: parsed,
    );
  }

  Future<Map<String, dynamic>> release({
    required int gameId,
    String? token,
    int? xUserId,
  }) async {
    // Ruta actual para liberar selección
    final uri = Uri.parse('$baseUrl/api/games/$gameId/selection');
    final headers = _headers(token: token, xUserId: xUserId);

    _log('RELEASE-REQ', uri, headers);
    http.Response res;
    try {
      res = await _client
          .delete(uri, headers: headers)
          .timeout(const Duration(seconds: 10));
    } on TimeoutException {
      return _fail(
        status: null,
        code: 'NETWORK_ERROR',
        message: 'Tiempo de espera agotado',
      );
    } on SocketException {
      return _fail(
        status: null,
        code: 'NETWORK_ERROR',
        message: 'Sin conexión',
      );
    } catch (e) {
      return _fail(status: null, code: 'UNKNOWN', message: e.toString());
    }

    _log('RELEASE-RES', uri, headers, null, res.statusCode, res.body);

    Map<String, dynamic>? parsed;
    try {
      parsed = res.body.isEmpty ? null : jsonDecode(res.body);
    } catch (_) {
      parsed = null;
    }

    if (res.statusCode >= 200 && res.statusCode < 300) {
      return _ok(res, parsed);
    }

    // 404 = no existía la reserva; el controller lo trata como OK para continuar
    if (res.statusCode == 404) {
      return _fail(
        status: 404,
        code: 'NOT_FOUND',
        message: 'Reserva no existe',
        data: parsed,
      );
    }

    // Fallback con X-USER-ID si 401
    if (res.statusCode == 401 && xUserId != null) {
      final devHeaders = {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        'X-USER-ID': xUserId.toString(),
      };

      _log('RELEASE-REQ(DEV)', uri, devHeaders);
      try {
        final devRes = await _client
            .delete(uri, headers: devHeaders)
            .timeout(const Duration(seconds: 10));

        _log(
          'RELEASE-RES(DEV)',
          uri,
          devHeaders,
          null,
          devRes.statusCode,
          devRes.body,
        );

        Map<String, dynamic>? devParsed;
        try {
          devParsed = devRes.body.isEmpty ? null : jsonDecode(devRes.body);
        } catch (_) {
          devParsed = null;
        }

        if (devRes.statusCode >= 200 && devRes.statusCode < 300) {
          return _ok(devRes, devParsed);
        }
        if (devRes.statusCode == 404) {
          return _fail(
            status: 404,
            code: 'NOT_FOUND',
            message: 'Reserva no existe',
            data: devParsed,
          );
        }

        return _fail(
          status: devRes.statusCode,
          code: (devParsed?['code'] ?? 'HTTP_${devRes.statusCode}').toString(),
          message:
              (devParsed?['message'] ??
                      'Error HTTP ${devRes.statusCode} al liberar reserva')
                  .toString(),
          data: devParsed,
        );
      } on TimeoutException {
        return _fail(
          status: null,
          code: 'NETWORK_ERROR',
          message: 'Tiempo de espera agotado',
        );
      } on SocketException {
        return _fail(
          status: null,
          code: 'NETWORK_ERROR',
          message: 'Sin conexión',
        );
      } catch (e) {
        return _fail(status: null, code: 'UNKNOWN', message: e.toString());
      }
    }

    return _fail(
      status: res.statusCode,
      code: (parsed?['code'] ?? 'HTTP_${res.statusCode}').toString(),
      message:
          (parsed?['message'] ??
                  'Error HTTP ${res.statusCode} al liberar reserva')
              .toString(),
      data: parsed,
    );
  }

  Future<Map<String, dynamic>> getMySelection({
    String? token,
    int? xUserId, // ← en la misma línea
  }) async {
    final uri = Uri.parse('$baseUrl/api/games/my-selection');
    final headers = _headers(token: token, xUserId: xUserId);

    _log('MYSEL-REQ', uri, headers);
    http.Response res;
    try {
      res = await _client
          .get(uri, headers: headers)
          .timeout(const Duration(seconds: 10));
    } on TimeoutException {
      return _fail(status: null, code: 'NETWORK_ERROR', message: 'Timeout');
    } on SocketException {
      return _fail(
        status: null,
        code: 'NETWORK_ERROR',
        message: 'Sin conexión',
      );
    } catch (e) {
      return _fail(status: null, code: 'UNKNOWN', message: e.toString());
    }

    _log('MYSEL-RES', uri, headers, null, res.statusCode, res.body);

    Map<String, dynamic>? parsed;
    try {
      parsed = res.body.isEmpty ? null : jsonDecode(res.body);
    } catch (_) {
      parsed = null;
    }

    if (res.statusCode >= 200 && res.statusCode < 300) {
      // Normaliza para que tengas "data" directo
      final Map<String, dynamic>? core = (parsed is Map<String, dynamic>)
          ? (parsed['data'] is Map<String, dynamic> ? parsed['data'] : parsed)
          : null;
      return {'ok': true, 'status': res.statusCode, 'data': core};
    }

    return _fail(
      status: res.statusCode,
      code: (parsed?['code'] ?? 'HTTP_${res.statusCode}').toString(),
      message: (parsed?['message'] ?? 'Error obteniendo selección').toString(),
      data: parsed,
    );
  }

  Future<Map<String, dynamic>> getNotifications({
    String? token,
    int? xUserId,
    bool unreadOnly = true, // <-- filtro por no leídas
    int page = 1,
    int perPage = 50,
  }) async {
    final q = unreadOnly
        ? '?unread=1&page=$page&per_page=$perPage'
        : '?page=$page&per_page=$perPage';

    final uri = Uri.parse('$baseUrl/api/notifications$q');
    final headers = _headers(token: token, xUserId: xUserId);

    _log('NOTIFS-REQ', uri, headers);
    http.Response res;
    try {
      res = await _client
          .get(uri, headers: headers)
          .timeout(const Duration(seconds: 10));
    } catch (e) {
      return _fail(status: null, code: 'NETWORK_ERROR', message: e.toString());
    }

    _log('NOTIFS-RES', uri, headers, null, res.statusCode, res.body);

    Map<String, dynamic>? parsed;
    try {
      parsed = res.body.isEmpty ? null : jsonDecode(res.body);
    } catch (_) {
      parsed = null;
    }

    if (res.statusCode >= 200 && res.statusCode < 300) {
      // El backend responde: { items: [...], page, per_page, total }
      final List<dynamic> items = (parsed?['items'] as List?) ?? const [];
      return {'ok': true, 'status': res.statusCode, 'data': items};
    }

    return _fail(
      status: res.statusCode,
      code: (parsed?['code'] ?? 'HTTP_${res.statusCode}').toString(),
      message: (parsed?['message'] ?? 'Error obteniendo notificaciones')
          .toString(),
      data: parsed,
    );
  }

  Future<Map<String, dynamic>> markNotificationsRead({
    required List<int> ids,
    String? token,
    int? xUserId,
  }) async {
    final uri = Uri.parse('$baseUrl/api/notifications/read');
    final headers = _headers(token: token, xUserId: xUserId);
    final body = jsonEncode({"ids": ids});

    _log('NOTIFS-READ-REQ', uri, headers, body);
    http.Response res;
    try {
      res = await _client
          .patch(uri, headers: headers, body: body)
          .timeout(const Duration(seconds: 10));
    } catch (e) {
      return _fail(status: null, code: 'NETWORK_ERROR', message: e.toString());
    }
    _log('NOTIFS-READ-RES', uri, headers, null, res.statusCode, res.body);

    Map<String, dynamic>? parsed;
    try {
      parsed = res.body.isEmpty ? null : jsonDecode(res.body);
    } catch (_) {
      parsed = null;
    }

    if (res.statusCode >= 200 && res.statusCode < 300) {
      return {'ok': true, 'status': res.statusCode, 'data': parsed};
    }
    return _fail(
      status: res.statusCode,
      code: (parsed?['code'] ?? 'HTTP_${res.statusCode}').toString(),
      message:
          (parsed?['message'] ?? 'Error marcando notificaciones como leídas')
              .toString(),
      data: parsed,
    );
  }

  Future<Map<String, dynamic>> getHistory({
    String? token,
    int? xUserId,
    int page = 1,
    int perPage = 50,
  }) async {
    final uri = Uri.parse(
      '$baseUrl/api/games/history?page=$page&per_page=$perPage',
    );
    final headers = _headers(token: token, xUserId: xUserId);

    _log('HISTORY-REQ', uri, headers);
    http.Response res;
    try {
      res = await _client
          .get(uri, headers: headers)
          .timeout(const Duration(seconds: 10));
    } on TimeoutException {
      return _fail(status: null, code: 'NETWORK_ERROR', message: 'Timeout');
    } on SocketException {
      return _fail(
        status: null,
        code: 'NETWORK_ERROR',
        message: 'Sin conexión',
      );
    } catch (e) {
      return _fail(status: null, code: 'UNKNOWN', message: e.toString());
    }

    _log('HISTORY-RES', uri, headers, null, res.statusCode, res.body);

    Map<String, dynamic>? parsed;
    try {
      parsed = res.body.isEmpty ? null : jsonDecode(res.body);
    } catch (_) {
      parsed = null;
    }

    if (res.statusCode >= 200 && res.statusCode < 300) {
      // Backend devuelve: { items: [...], page, per_page, total }
      final List<dynamic> items = (parsed?['items'] as List?) ?? const [];
      return {
        'ok': true,
        'status': res.statusCode,
        'data': items, // 👈 en el controller usarás directamente la lista
        'page': parsed?['page'] ?? page,
        'per_page': parsed?['per_page'] ?? perPage,
        'total': (parsed?['total'] as num?)?.toInt() ?? items.length,
      };
    }

    return _fail(
      status: res.statusCode,
      code: (parsed?['code'] ?? 'HTTP_${res.statusCode}').toString(),
      message: (parsed?['message'] ?? 'Error obteniendo historial').toString(),
      data: parsed,
    );
  }

  Future<Map<String, dynamic>> adminUpdateGame({
    required int gameId,
    int? lotteryId,
    required String playedDate,
    required String playedTime,
    String? token,
    int? xUserId,
  }) async {
    final uri = Uri.parse('$baseUrl/api/admin/games/$gameId');
    final headers = _headers(token: token, xUserId: xUserId);

    final body = jsonEncode({
      if (lotteryId != null) 'lottery_id': lotteryId,
      'played_date': playedDate, // <- siempre presentes
      'played_time': playedTime, // <- siempre presentes
    });

    _log('ADMIN-GAME-PATCH-REQ', uri, headers, body);
    http.Response res;
    try {
      res = await _client
          .patch(uri, headers: headers, body: body)
          .timeout(const Duration(seconds: 10));
    } catch (e) {
      return _fail(status: null, code: 'NETWORK_ERROR', message: e.toString());
    }

    _log('ADMIN-GAME-PATCH-RES', uri, headers, null, res.statusCode, res.body);

    Map<String, dynamic>? parsed;
    try {
      parsed = res.body.isEmpty ? null : jsonDecode(res.body);
    } catch (_) {
      parsed = null;
    }

    if (res.statusCode >= 200 && res.statusCode < 300) {
      return {'ok': true, 'status': res.statusCode, 'data': parsed?['item']};
    }

    return _fail(
      status: res.statusCode,
      code: (parsed?['code'] ?? 'HTTP_${res.statusCode}').toString(),
      message:
          (parsed?['error'] ?? parsed?['message'] ?? 'Error actualizando juego')
              .toString(),
      data: parsed,
    );
  }

  Future<Map<String, dynamic>> peekSchedule({
    String? token,
    int? xUserId,
  }) async {
    final uri = Uri.parse('$baseUrl/api/me/notifications/peek-schedule');
    final headers = _headers(token: token, xUserId: xUserId);

    _log('PEEK-SCHEDULE-REQ', uri, headers);
    http.Response res;
    try {
      res = await _client
          .get(uri, headers: headers)
          .timeout(const Duration(seconds: 10));
    } catch (e) {
      return _fail(status: null, code: 'NETWORK_ERROR', message: e.toString());
    }

    _log('PEEK-SCHEDULE-RES', uri, headers, null, res.statusCode, res.body);

    Map<String, dynamic>? parsed;
    try {
      parsed = res.body.isEmpty ? null : jsonDecode(res.body);
    } catch (_) {
      parsed = null;
    }

    if (res.statusCode >= 200 && res.statusCode < 300) {
      final Map<String, dynamic>? item =
          (parsed is Map<String, dynamic> && parsed.isNotEmpty) ? parsed : null;
      // devolver el item directamente (o {} si no hay)
      return item ?? <String, dynamic>{};
    }

    return _fail(
      status: res.statusCode,
      code: (parsed?['code'] ?? 'HTTP_${res.statusCode}').toString(),
      message: (parsed?['message'] ?? 'Error en peek-schedule').toString(),
      data: parsed,
    );
  }
}
