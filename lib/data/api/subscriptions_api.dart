import 'dart:convert';
import 'dart:developer' as dev;
import 'package:http/http.dart' as http;

class SubscriptionsApi {
  final String baseUrl;
  SubscriptionsApi({required this.baseUrl});

  /// GET /api/subscriptions/status
  /// Devuelve: { isPremium, status, expiresAt, userId, entitlement }
  Future<Map<String, dynamic>> getStatus({required String token}) async {
    final uri = Uri.parse('$baseUrl/api/subscriptions/status');
    dev.log('SubscriptionsApi.getStatus -> GET $uri');

    final res = await http.get(
      uri,
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );

    dev.log('SubscriptionsApi.getStatus -> status: ${res.statusCode}');
    dev.log('SubscriptionsApi.getStatus -> body: ${res.body}');

    if (res.statusCode >= 200 && res.statusCode < 300) {
      final data = jsonDecode(res.body);
      if (data is Map<String, dynamic>) return data;
      throw Exception('Respuesta inesperada del servidor: ${res.body}');
    } else {
      throw Exception(
        'Error ${res.statusCode} al consultar status: ${res.body}',
      );
    }
  }

  /// POST /api/subscriptions/cancel
  /// Cancela la suscripción activa del usuario.
  Future<void> cancel({required String token}) async {
    final uri = Uri.parse('$baseUrl/api/subscriptions/cancel');
    dev.log('SubscriptionsApi.cancel -> POST $uri');

    final res = await http.post(
      uri,
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );

    dev.log('SubscriptionsApi.cancel -> status: ${res.statusCode}');
    dev.log('SubscriptionsApi.cancel -> body: ${res.body}');

    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception(
        'Error ${res.statusCode} al cancelar: ${res.body}',
      );
    }
  }
}
