// lib/data/api/admin_referrals_api.dart
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'package:base_app/data/session/session_manager.dart';
import 'package:base_app/data/models/referrals_summary.dart';

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
}
