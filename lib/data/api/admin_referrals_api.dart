// lib/data/api/admin_referrals_api.dart
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'package:base_app/data/session/session_manager.dart';
import 'package:base_app/data/models/referrals_summary.dart';
import 'package:base_app/data/models/top_referrer.dart';
import 'package:base_app/domain/models/commission_request.dart';
import 'package:base_app/data/models/admin_user_detail.dart';
import 'package:base_app/data/models/commission_breakdown.dart';
import 'dart:io';
import 'package:base_app/data/models/payout_batch.dart';
import 'package:base_app/data/models/payout_batch_detail.dart';

/// API para endpoints de referidos del admin.
class AdminReferralsApi {
  final String baseUrl;
  const AdminReferralsApi({required this.baseUrl});

  /// GET /api/admin/referrals/summary
  /// Respuesta esperada:
  /// `{ ok: true, total: 123, active: 45, inactive: 78 }`
  Future<ReferralsSummary> fetchSummary() async {
    final token = await SessionManager().getToken();
    final uri = Uri.parse('$baseUrl/api/admin/referrals/summary');

    final res = await http
        .get(
          uri,
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
          },
        )
        .timeout(const Duration(seconds: 15));

    if (kDebugMode) {
      debugPrint('[admin/referrals/summary] ${res.statusCode} ${res.body}');
    }

    if (res.statusCode != 200) {
      throw Exception('HTTP ${res.statusCode}: ${res.body}');
    }

    final Map<String, dynamic> body =
        json.decode(res.body) as Map<String, dynamic>;

    final ok = body['ok'] == true;
    if (!ok) {
      throw Exception('Respuesta no OK: ${res.body}');
    }

    return ReferralsSummary.fromApiResponse(body);
  }

  /// GET /api/admin/referrals/top
  /// Respuesta esperada:
  /// `{ ok: true, items: [ { user_id: 1, name: "...", phone: "...", active_count: 5 } ] }`
  Future<List<TopReferrer>> fetchTopReferrers() async {
    final token = await SessionManager().getToken();
    final uri = Uri.parse('$baseUrl/api/admin/referrals/top');

    if (kDebugMode) {
      final shortToken = token != null && token.length > 12
          ? '${token.substring(0, 12)}...'
          : '$token';
      debugPrint('[admin/referrals/top] -> GET $uri');
      debugPrint('[admin/referrals/top] token(head)=$shortToken');
    }

    final res = await http
        .get(
          uri,
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
          },
        )
        .timeout(const Duration(seconds: 15));

    if (kDebugMode) {
      debugPrint('[admin/referrals/top] ${res.statusCode} ${res.body}');
    }

    if (res.statusCode != 200) {
      throw Exception('HTTP ${res.statusCode}: ${res.body}');
    }

    final body = json.decode(res.body) as Map<String, dynamic>;
    if (body['ok'] != true) throw Exception('Respuesta no OK');

    final items = (body['items'] as List).cast<Map<String, dynamic>>();
    return items.map((e) => TopReferrer.fromMap(e)).toList();
  }

  /// GET /api/admin/referrals/commission-requests
  /// Devuelve lista de solicitudes de retiro (payout_requests).
  Future<List<CommissionRequest>> fetchCommissionRequests({
    String? status, // 'requested' | 'processing' | 'paid' | etc.
    int limit = 50,
    int offset = 0,
  }) async {
    final token = await SessionManager().getToken();

    final uri = Uri.parse('$baseUrl/api/admin/referrals/commission-requests')
        .replace(
          queryParameters: {
            if (status != null && status.isNotEmpty) 'status': status,
            'limit': '$limit',
            'offset': '$offset',
          },
        );

    if (kDebugMode) {
      debugPrint('[admin/referrals/commission-requests] -> GET $uri');
    }

    final res = await http
        .get(
          uri,
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
          },
        )
        .timeout(const Duration(seconds: 15));

    if (kDebugMode) {
      debugPrint(
        '[admin/referrals/commission-requests] ${res.statusCode} ${res.body}',
      );
    }

    if (res.statusCode != 200) {
      throw Exception('HTTP ${res.statusCode}: ${res.body}');
    }

    final body = json.decode(res.body) as Map<String, dynamic>;
    if (body['ok'] != true) throw Exception('Respuesta no OK');

    final items = (body['items'] as List).cast<Map<String, dynamic>>();
    return items.map((e) => CommissionRequest.fromJson(e)).toList();
  }

  /// GET /api/admin/referrals/user-detail/:userId
  /// Devuelve: nombres, identificación, si es PRO y los datos bancarios más recientes.
  Future<AdminUserDetail> fetchUserDetail(int userId) async {
    final token = await SessionManager().getToken();
    final uri = Uri.parse('$baseUrl/api/admin/referrals/user-detail/$userId');

    if (kDebugMode) {
      debugPrint('[admin/referrals/user-detail] -> GET $uri');
    }

    final res = await http
        .get(
          uri,
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
          },
        )
        .timeout(const Duration(seconds: 15));

    if (kDebugMode) {
      debugPrint('[admin/referrals/user-detail] ${res.statusCode} ${res.body}');
    }

    if (res.statusCode != 200) {
      throw Exception('HTTP ${res.statusCode}: ${res.body}');
    }

    final Map<String, dynamic> body =
        json.decode(res.body) as Map<String, dynamic>;

    if (body['ok'] != true) {
      throw Exception('Respuesta no OK: ${res.body}');
    }

    // Soporta dos formatos de respuesta:
    // a) { ok:true, item:{...} }
    // b) { ok:true, ...campos... }
    final data = (body['item'] ?? body) as Map<String, dynamic>;
    return AdminUserDetail.fromJson(data);
  }

  /// GET /api/admin/referrals/commission-requests/:id/breakdown
  Future<CommissionRequestBreakdown> fetchCommissionBreakdown(
    int requestId,
  ) async {
    final token = await SessionManager().getToken();
    final uri = Uri.parse(
      '$baseUrl/api/admin/referrals/commission-requests/$requestId/breakdown',
    );

    if (kDebugMode) {
      debugPrint('[admin/referrals/breakdown] -> GET $uri');
    }

    final res = await http
        .get(
          uri,
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
          },
        )
        .timeout(const Duration(seconds: 15));

    if (kDebugMode) {
      debugPrint('[admin/referrals/breakdown] ${res.statusCode} ${res.body}');
    }

    if (res.statusCode != 200) {
      throw Exception('HTTP ${res.statusCode}: ${res.body}');
    }

    final Map<String, dynamic> body =
        json.decode(res.body) as Map<String, dynamic>;
    if (body['ok'] != true) {
      throw Exception('Respuesta no OK: ${res.body}');
    }

    final data = (body['item'] ?? body) as Map<String, dynamic>;
    return CommissionRequestBreakdown.fromJson(data);
  }

  /// POST /api/admin/referrals/payout-requests/:id/reject
  Future<void> rejectPayoutRequest({
    required int id,
    required String reason,
  }) async {
    final token = await SessionManager().getToken();
    final uri = Uri.parse(
      '$baseUrl/api/admin/referrals/payout-requests/$id/reject',
    );

    if (kDebugMode) {
      debugPrint('[admin/referrals/reject] -> POST $uri');
    }

    final res = await http
        .post(
          uri,
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
          },
          body: json.encode({'reason': reason}),
        )
        .timeout(const Duration(seconds: 15));

    if (kDebugMode) {
      debugPrint('[admin/referrals/reject] ${res.statusCode} ${res.body}');
    }

    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception('HTTP ${res.statusCode}: ${res.body}');
    }
  }

  /// POST /api/admin/referrals/payout-batches
  /// Crea un lote de pago con nota y (opcional) evidencias.
  /// - Si [files] está vacío, envía JSON.
  /// - Si [files] tiene elementos, envía multipart con un campo request_ids_json.
  Future<Map<String, dynamic>> createPayoutBatch({
    required List<int> requestIds,
    String note = '',
    List<File> files = const [],
  }) async {
    final token = await SessionManager().getToken();
    final uri = Uri.parse('$baseUrl/api/admin/referrals/payout-batches');

    // Sin adjuntos -> JSON simple
    if (files.isEmpty) {
      final res = await http
          .post(
            uri,
            headers: {
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json',
            },
            body: json.encode({'request_ids': requestIds, 'note': note}),
          )
          .timeout(const Duration(seconds: 30));

      if (kDebugMode) {
        debugPrint('[admin/payout-batches] JSON ${res.statusCode} ${res.body}');
      }

      if (res.statusCode != 200) {
        throw Exception('HTTP ${res.statusCode}: ${res.body}');
      }
      final body = json.decode(res.body) as Map<String, dynamic>;
      if (body['ok'] != true) {
        throw Exception('Respuesta no OK: ${res.body}');
      }
      return (body['item'] ?? body) as Map<String, dynamic>;
    }

    // Con adjuntos -> multipart
    final req = http.MultipartRequest('POST', uri);
    if (token != null) req.headers['Authorization'] = 'Bearer $token';

    // Campo con los IDs en JSON para el backend
    req.fields['request_ids'] = json.encode(requestIds);
    req.fields['note'] = note;

    // Convertir cada File -> MultipartFile y agregarlo
    for (final f in files) {
      if (!await f.exists()) continue;
      final mf = await http.MultipartFile.fromPath('files', f.path);
      req.files.add(mf);
    }

    final streamed = await req.send();
    final res = await http.Response.fromStream(streamed);

    if (kDebugMode) {
      debugPrint(
        '[admin/payout-batches] MULTIPART ${res.statusCode} ${res.body}',
      );
    }

    if (res.statusCode != 200) {
      throw Exception('HTTP ${res.statusCode}: ${res.body}');
    }
    final body = json.decode(res.body) as Map<String, dynamic>;
    if (body['ok'] != true) {
      throw Exception('Respuesta no OK: ${res.body}');
    }
    return (body['item'] ?? body) as Map<String, dynamic>;
  }

  Future<List<PayoutBatch>> fetchPayoutBatches({
    int limit = 50,
    int offset = 0,
  }) async {
    final token = await SessionManager().getToken();
    final uri = Uri.parse(
      '$baseUrl/api/admin/referrals/payout-batches',
    ).replace(queryParameters: {'limit': '$limit', 'offset': '$offset'});

    if (kDebugMode) debugPrint('[admin/referrals/payout-batches] GET $uri');

    final res = await http
        .get(
          uri,
          headers: {
            'Authorization': 'Bearer $token',
            'Accept': 'application/json',
            'Content-Type': 'application/json',
          },
        )
        .timeout(const Duration(seconds: 15));

    if (kDebugMode) {
      debugPrint(
        '[admin/referrals/payout-batches] ${res.statusCode} ${res.body}',
      );
    }

    if (res.statusCode != 200) {
      throw Exception('HTTP ${res.statusCode}: ${res.body}');
    }

    final decoded = json.decode(res.body);
    List<dynamic> items;
    if (decoded is List) {
      items = decoded;
    } else if (decoded is Map<String, dynamic>) {
      final anyList = decoded['items'] ?? decoded['data'] ?? [];
      if (anyList is! List) {
        throw Exception('Formato inesperado en payout-batches');
      }
      items = anyList;
    } else {
      throw Exception('Formato inesperado en payout-batches');
    }

    return PayoutBatch.listFromJson(items);
  }

Future<PayoutBatchDetails> fetchPayoutBatchDetails(int batchId) async {
  final token = await SessionManager().getToken();
  final uri = Uri.parse(
    '$baseUrl/api/admin/referrals/payout-batches/$batchId/details',
  );

  if (kDebugMode) debugPrint('[admin/referrals/payout-batches/details] GET $uri');

  final res = await http
      .get(
        uri,
        headers: {
          'Authorization': 'Bearer $token',
          'Accept': 'application/json',
          'Content-Type': 'application/json',
        },
      )
      .timeout(const Duration(seconds: 15));

  if (res.statusCode != 200) {
    throw Exception('HTTP ${res.statusCode}: ${res.body}');
  }

  final decoded = json.decode(res.body);
  final map = decoded is Map<String, dynamic>
      ? (decoded['item'] ?? decoded) as Map<String, dynamic>
      : (throw Exception('Formato inesperado en details'));

  return PayoutBatchDetails.fromJson(map); // usa el constructor que tengas
}

}
