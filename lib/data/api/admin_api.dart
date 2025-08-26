import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:base_app/data/session/session_manager.dart';
import 'package:base_app/core/config/env.dart';

class AdminApi {
  final String baseUrl;
  AdminApi({String? baseUrl}) : baseUrl = baseUrl ?? Env.apiBaseUrl;

  Future<Map<String, dynamic>> fetchDashboardSummary() async {
    final token = await SessionManager().getToken();
    final userId = await SessionManager().getUserId();

    final uri = Uri.parse('$baseUrl/api/admin/dashboard/summary');
    final res = await http.get(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': token != null ? 'Bearer $token' : '',
        'X-User-Id': userId?.toString() ?? '',
      },
    );

    if (res.statusCode != 200) {
      throw Exception('Error ${res.statusCode}: ${res.body}');
    }
    final data = json.decode(res.body) as Map<String, dynamic>;
    if (data['ok'] != true) {
      throw Exception(data['error'] ?? 'Error en respuesta');
    }
    return data;
  }
}
