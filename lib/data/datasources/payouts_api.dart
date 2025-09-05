import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:base_app/domain/models/payout_request.dart';

typedef TokenProvider = Future<String?> Function();

class PayoutsApi {
  final String baseUrl;                // e.g. http://127.0.0.1:8000
  final TokenProvider tokenProvider;   // cómo obtienes tu JWT

  PayoutsApi({required this.baseUrl, required this.tokenProvider});

  Future<void> createPayoutRequest(PayoutRequestInput input) async {
    final token = await tokenProvider();
    final uri = Uri.parse('$baseUrl/api/me/payouts/requests');

    final resp = await http.post(
      uri,
      headers: {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      },
      body: jsonEncode(input.toJson()),
    );

    if (resp.statusCode != 200) {
      try {
        final body = jsonDecode(resp.body);
        throw Exception(body['error'] ?? 'Error creando la solicitud');
      } catch (_) {
        throw Exception('Error creando la solicitud (${resp.statusCode})');
      }
    }
  }
}
