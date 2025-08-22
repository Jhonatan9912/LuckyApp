import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:base_app/data/session/session_manager.dart';

class AdminApi {
  final String baseUrl;
  AdminApi({this.baseUrl = 'http://10.0.2.2:8000'});

  Future<Map<String, dynamic>> fetchDashboardSummary() async {
    final token = await SessionManager().getToken();
    final userId = await SessionManager().getUserId();

    final uri = Uri.parse('$baseUrl/api/admin/dashboard/summary');
    final res = await http.get(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': token != null ? 'Bearer $token' : '',
        // Para el guard simple del backend demo (si no usas sesión):
        'X-User-Id': userId?.toString() ?? '',
      },
    );

    if (res.statusCode != 200) {
      throw Exception('Error ${res.statusCode}: ${res.body}');
    }
    final data = json.decode(res.body) as Map<String, dynamic>;
    if (!(data['ok'] == true)) {
      throw Exception(data['error'] ?? 'Error en respuesta');
    }
    return data;
  }
}