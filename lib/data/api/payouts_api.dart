// lib/data/api/payouts_api.dart
import 'dart:convert';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'package:base_app/domain/models/bank.dart';
import 'package:base_app/domain/models/payout_request.dart';
import 'package:base_app/data/session/session_manager.dart';

class PayoutsApi {
  final String baseUrl;
  final SessionManager session;

  PayoutsApi({required this.baseUrl, required this.session});

  static const _timeout = Duration(seconds: 15);

  Future<Map<String, String>> _headers() async {
    final token = await session.getToken();
    return {
      'Accept': 'application/json',
      'Content-Type': 'application/json',
      if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
    };
  }

  /// GET /api/meta/banks?active=1[&entity_type=BANK]
  /// Ajusta los nombres de query si tu backend usa otros (ej. type=).
  Future<List<Bank>> fetchBanks({
    bool onlyActive = true,
    String? entityType, // 'BANK' | 'SEDPE' | 'CF'
  }) async {
    final query = <String, String>{};
    if (onlyActive) query['active'] = '1';
    if (entityType != null && entityType.isNotEmpty) {
      query['entity_type'] = entityType;
    }

    final uri =
        Uri.parse('$baseUrl/api/meta/banks').replace(queryParameters: query);
    final res = await http.get(uri, headers: await _headers()).timeout(_timeout);

    if (kDebugMode) {
      debugPrint('[PayoutsApi.fetchBanks] GET $uri -> ${res.statusCode}');
      debugPrint('[PayoutsApi.fetchBanks] body: ${res.body}');
    }

    if (res.statusCode >= 200 && res.statusCode < 300) {
      dynamic data;
      try {
        data = json.decode(res.body);
      } catch (e) {
        throw Exception('Respuesta de bancos inválida (JSON).');
      }

      if (data is List) {
        return data
            .map((e) => Bank.fromJson(e as Map<String, dynamic>))
            .toList();
      }
      if (data is Map && data['items'] is List) {
        return (data['items'] as List)
            .map((e) => Bank.fromJson(e as Map<String, dynamic>))
            .toList();
      }
      throw Exception('Formato de respuesta de bancos no reconocido.');
    }

    throw Exception('No se pudo cargar bancos (${res.statusCode}).');
  }

  /// POST /api/me/payouts/requests
  /// Devuelve true si el backend confirma la creación; de lo contrario lanza Exception con el mensaje.
  Future<bool> submitPayoutRequest(PayoutRequestInput input) async {
    final uri = Uri.parse('$baseUrl/api/me/payouts/requests');

    final payload = input.toJson();
    final res = await http
        .post(uri, headers: await _headers(), body: json.encode(payload))
        .timeout(_timeout);

    if (kDebugMode) {
      debugPrint(
          '[PayoutsApi.submitPayoutRequest] POST $uri -> ${res.statusCode}');
      debugPrint(
          '[PayoutsApi.submitPayoutRequest] payload: ${json.encode(payload)}');
      debugPrint('[PayoutsApi.submitPayoutRequest] body: ${res.body}');
    }

    // Éxito (incluye 201 Created)
    if (res.statusCode >= 200 && res.statusCode < 300) {
      if (res.body.isEmpty) return true;

      try {
        final body = json.decode(res.body);
        if (body is Map<String, dynamic>) {
          // Formato estándar de nuestras rutas: { ok: true, request: {...} }
          if (body['ok'] == true) return true;

          // Aceptar variantes donde venga el objeto de la solicitud
          if (body['request'] is Map) return true;
          if (body['id'] != null || body['request_id'] != null) return true;

          // Si viene ok=false con error, lo propagamos
          if (body['ok'] == false && body['error'] != null) {
            throw Exception(body['error'].toString());
          }
        }
      } catch (_) {
        // Si no es JSON pero fue 2xx, lo consideramos OK
      }
      return true;
    }

    // Error: intenta leer mensaje del backend
    String message = 'Error ${res.statusCode} al crear la solicitud de retiro.';
    try {
      final body = json.decode(res.body);
      if (body is Map && body['error'] != null) {
        message = body['error'].toString();
      }
    } catch (_) {
      // cuerpo no-JSON; usamos el status
    }
    throw Exception(message);
  }
}
