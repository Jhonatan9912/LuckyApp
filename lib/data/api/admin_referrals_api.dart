// lib/data/api/admin_referrals_api.dart
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'package:base_app/data/session/session_manager.dart';
import 'package:base_app/data/models/referrals_summary.dart';
import 'package:base_app/data/models/top_referrer.dart';

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
}
