import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

// 👇 NUEVO: modo de juego (3, 4, quinta)
import 'package:base_app/presentation/screens/dashboard/logic/game_mode.dart';

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
  }) =>
      {
        'ok': false,
        'status': status,
        'code': code,
        'message': message,
        'data': data,
      };
// ============================================================
// ✅ UTILIDAD: Construir números de 5 dígitos (00000–99999)
// ============================================================
List<int> buildFiveDigits({
  required List<int> base4Numbers, // 0..9999
  required List<int> fifths,       // 0..9
}) {
  if (base4Numbers.length != fifths.length) {
    throw ArgumentError('base4Numbers y fifths deben tener el mismo tamaño');
  }

  return List.generate(base4Numbers.length, (i) {
    final base = base4Numbers[i];
    final fifth = fifths[i];

    if (base < 0 || base > 9999) {
      throw ArgumentError('base4Numbers[$i] fuera de rango: $base');
    }
    if (fifth < 0 || fifth > 9) {
      throw ArgumentError('fifths[$i] fuera de rango: $fifth');
    }

    return (base * 10) + fifth; // 00000..99999
  });
}

Future<Map<String, dynamic>> generateByMode({
  String? token,
  int? xUserId,
  required GameMode mode,
}) async {
  final digits = (mode == GameMode.quinta) ? 5 : mode.baseDigits;

  final uri = Uri.parse(
    '$baseUrl/api/games/generate?digits=$digits&mode=${Uri.encodeComponent(mode.apiValue)}',
  );

  final headers = _headers(token: token, xUserId: null);
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
    final data = parsed is Map<String, dynamic>
        ? (parsed['data'] ?? parsed)
        : null;

    return {'ok': true, 'status': res.statusCode, 'data': data};
  }

  return _fail(
    status: res.statusCode,
    code: parsed?['code'] ?? 'HTTP_${res.statusCode}',
    message: parsed?['message'] ?? 'Error generando números',
    data: parsed,
  );
}


// ✅ COMPAT: ahora respeta digits=5 también
Future<Map<String, dynamic>> generate({
  String? token,
  int? xUserId,
  int digits = 3,
}) async {
  final GameMode mode;
  if (digits == 5) {
    mode = GameMode.quinta;
  } else if (digits == 4) {
    mode = GameMode.digits4;
  } else if (digits == 2) {
    mode = GameMode.digits2;
  } else {
    mode = GameMode.digits3;
  }
  return generateByMode(token: token, xUserId: xUserId, mode: mode);
}
Future<Map<String, dynamic>> commitByMode({
  int? gameId,
  required List<int> numbers,
  String? token,
  int? xUserId,
  required GameMode mode,
  List<int>? fifths,
}) async {
  final uri = Uri.parse('$baseUrl/api/games/commit');

  final bodyMap = <String, dynamic>{
    'numbers': numbers,
    'digits': (mode == GameMode.quinta) ? 5 : mode.baseDigits,
    'mode': mode.apiValue,
  };

  if (gameId != null) {
    bodyMap['game_id'] = gameId;
  }

  if (mode == GameMode.quinta) {
    bodyMap['extras'] = {
      'fifths': fifths ?? [],
    };
  }

  final payload = jsonEncode(bodyMap);
  final headers = _headers(token: token, xUserId: null);

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

  return _fail(
    status: res.statusCode,
    code: parsed?['code'] ?? 'HTTP_${res.statusCode}',
    message: parsed?['message'] ?? 'Error al guardar selección',
    data: parsed,
  );
}


Future<Map<String, dynamic>> commit({
  int? gameId,
  required List<int> numbers,
  String? token,
  int? xUserId,
  int digits = 3,
  List<int>? fifths, // 👈 agrega esto
}) async {
  final GameMode mode;
  if (digits == 5) {
    mode = GameMode.quinta;
  } else if (digits == 4) {
    mode = GameMode.digits4;
  } else if (digits == 2) {
    mode = GameMode.digits2;
  } else {
    mode = GameMode.digits3;
  }

  return commitByMode(
    gameId: gameId,
    numbers: numbers,
    token: token,
    xUserId: xUserId,
    mode: mode,
    fifths: fifths,
  );
}

  Future<Map<String, dynamic>> release({
    required int gameId,
    String? token,
    int? xUserId,
  }) async {
    final uri = Uri.parse('$baseUrl/api/games/$gameId/selection');
    final headers = _headers(token: token, xUserId: null);

    _log('RELEASE-REQ', uri, headers);

    http.Response res;
    try {
      res = await _client
          .delete(uri, headers: headers)
          .timeout(const Duration(seconds: 10));
    } on TimeoutException {
      return _fail(status: null, code: 'NETWORK_ERROR', message: 'Timeout');
    } on SocketException {
      return _fail(status: null, code: 'NETWORK_ERROR', message: 'Sin conexión');
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

    if (res.statusCode == 404) {
      return _fail(status: 404, code: 'NOT_FOUND', message: 'Reserva no existe', data: parsed);
    }

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

        _log('RELEASE-RES(DEV)', uri, devHeaders, null, devRes.statusCode, devRes.body);

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
          return _fail(status: 404, code: 'NOT_FOUND', message: 'Reserva no existe', data: devParsed);
        }

        return _fail(
          status: devRes.statusCode,
          code: (devParsed?['code'] ?? 'HTTP_${devRes.statusCode}').toString(),
          message: (devParsed?['message'] ?? 'Error HTTP ${devRes.statusCode} al liberar reserva').toString(),
          data: devParsed,
        );
      } on TimeoutException {
        return _fail(status: null, code: 'NETWORK_ERROR', message: 'Timeout');
      } on SocketException {
        return _fail(status: null, code: 'NETWORK_ERROR', message: 'Sin conexión');
      } catch (e) {
        return _fail(status: null, code: 'UNKNOWN', message: e.toString());
      }
    }

return _fail(
  status: res.statusCode,
  code: (parsed?['code'] ?? 'HTTP_${res.statusCode}').toString(),
  message: (parsed?['message'] ?? 'Error HTTP ${res.statusCode} al liberar reserva').toString(),
  data: parsed,
);
}

  

  // ============================================================
  // ✅ NUEVO: my-selection por modo
  // ============================================================
  Future<Map<String, dynamic>> getMySelectionByMode({
    String? token,
    int? xUserId,
    required GameMode mode,
  }) async {
    final digits = (mode == GameMode.quinta) ? 5 : mode.baseDigits;


    final uri = Uri.parse(
      '$baseUrl/api/games/my-selection?digits=$digits&mode=${Uri.encodeComponent(mode.apiValue)}',
    );
    final headers = _headers(token: token, xUserId: null);

    _log('MYSEL-REQ', uri, headers);

    http.Response res;
    try {
      res = await _client
          .get(uri, headers: headers)
          .timeout(const Duration(seconds: 10));
    } on TimeoutException {
      return _fail(status: null, code: 'NETWORK_ERROR', message: 'Timeout');
    } on SocketException {
      return _fail(status: null, code: 'NETWORK_ERROR', message: 'Sin conexión');
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

Future<Map<String, dynamic>> getMySelection({
  String? token,
  int? xUserId,
  int digits = 3,
}) async {
  final GameMode mode;
  if (digits == 5) {
    mode = GameMode.quinta;
  } else if (digits == 4) {
    mode = GameMode.digits4;
  } else if (digits == 2) {
    mode = GameMode.digits2;
  } else {
    mode = GameMode.digits3;
  }
  return getMySelectionByMode(token: token, xUserId: xUserId, mode: mode);
}


  Future<Map<String, dynamic>> getNotifications({
    String? token,
    int? xUserId,
    bool unreadOnly = true,
    int page = 1,
    int perPage = 50,
  }) async {
    final q = unreadOnly
        ? '?unread=1&page=$page&per_page=$perPage'
        : '?page=$page&per_page=$perPage';

    final uri = Uri.parse('$baseUrl/api/notifications$q');
    final headers = _headers(token: token, xUserId: null);

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
      final List<dynamic> items = (parsed?['items'] as List?) ?? const [];
      return {'ok': true, 'status': res.statusCode, 'data': items};
    }

    return _fail(
      status: res.statusCode,
      code: (parsed?['code'] ?? 'HTTP_${res.statusCode}').toString(),
      message: (parsed?['message'] ?? 'Error obteniendo notificaciones').toString(),
      data: parsed,
    );
  }

  Future<Map<String, dynamic>> markNotificationsRead({
    required List<int> ids,
    String? token,
    int? xUserId,
  }) async {
    final uri = Uri.parse('$baseUrl/api/notifications/read');
    final headers = _headers(token: token, xUserId: null);
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
      message: (parsed?['message'] ?? 'Error marcando notificaciones como leídas').toString(),
      data: parsed,
    );
  }

  Future<Map<String, dynamic>> getHistory({
    String? token,
    int? xUserId,
    int page = 1,
    int perPage = 50,
  }) async {
    final uri = Uri.parse('$baseUrl/api/games/history?page=$page&per_page=$perPage');
    final headers = _headers(token: token, xUserId: null);

    _log('HISTORY-REQ', uri, headers);

    http.Response res;
    try {
      res = await _client
          .get(uri, headers: headers)
          .timeout(const Duration(seconds: 10));
    } on TimeoutException {
      return _fail(status: null, code: 'NETWORK_ERROR', message: 'Timeout');
    } on SocketException {
      return _fail(status: null, code: 'NETWORK_ERROR', message: 'Sin conexión');
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
      final List<dynamic> items = (parsed?['items'] as List?) ?? const [];
      return {
        'ok': true,
        'status': res.statusCode,
        'data': items,
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
    final headers = _headers(token: token, xUserId: null);

    final body = jsonEncode({
      if (lotteryId != null) 'lottery_id': lotteryId,
      'played_date': playedDate,
      'played_time': playedTime,
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
      message: (parsed?['error'] ?? parsed?['message'] ?? 'Error actualizando juego').toString(),
      data: parsed,
    );
  }

  Future<Map<String, dynamic>> peekSchedule({
    String? token,
    int? xUserId,
  }) async {
    final uri = Uri.parse('$baseUrl/api/me/notifications/peek-schedule');
    final headers = _headers(token: token, xUserId: null);

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
