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

    /// POST /api/subscriptions/sync
  /// Envía el recibo de Google Play al backend para validarlo y activar PRO.
  /// Ajusta la ruta si tu backend usa otra.
  Future<Map<String, dynamic>> syncPurchase({
    required String token,
    required String productId,
    required String purchaseId,
    required String verificationData,
  }) async {
    final uri = Uri.parse('$baseUrl/api/subscriptions/sync'); // <-- cambia si tu API es distinta
    dev.log('SubscriptionsApi.syncPurchase -> POST $uri');

    final body = jsonEncode({
      'product_id': productId,
      'purchase_id': purchaseId,
      'verification_data': verificationData,
    });

    try {
      final res = await http
          .post(
            uri,
            headers: {
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: body,
          )
          .timeout(const Duration(seconds: 15));

      dev.log('SubscriptionsApi.syncPurchase -> status: ${res.statusCode}');
      dev.log('SubscriptionsApi.syncPurchase -> body: ${res.body}');

      Map<String, dynamic>? parsed;
      try {
        parsed = res.body.isEmpty ? null : jsonDecode(res.body);
      } catch (_) {
        parsed = null;
      }

      if (res.statusCode >= 200 && res.statusCode < 300) {
        return parsed ?? <String, dynamic>{'ok': true};
      }

      return <String, dynamic>{
        'ok': false,
        'status': res.statusCode,
        'code': (parsed?['code'] ?? 'HTTP_${res.statusCode}').toString(),
        'message':
            (parsed?['message'] ?? 'Error sincronizando compra').toString(),
        'data': parsed,
      };
    } catch (e) {
      return <String, dynamic>{
        'ok': false,
        'status': null,
        'code': 'NETWORK_ERROR',
        'message': 'No se pudo conectar con el servidor ($e)',
      };
    }
  }

}
