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

  String _join(String path) {
    if (baseUrl.endsWith('/')) {
      return '${baseUrl.substring(0, baseUrl.length - 1)}$path';
    }
    return '$baseUrl$path';
  }

  /// GET /api/meta/banks?active=1[&entity_type=BANK]
  Future<List<Bank>> fetchBanks({
    bool onlyActive = true,
    String? entityType, // 'BANK' | 'SEDPE' | 'CF'
  }) async {
    final query = <String, String>{};
    if (onlyActive) query['active'] = '1';
    if (entityType != null && entityType.isNotEmpty) {
      query['entity_type'] = entityType;
    }

    final uri = Uri.parse(_join('/api/meta/banks')).replace(queryParameters: query);
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
        return data.map((e) => Bank.fromJson(e as Map<String, dynamic>)).toList();
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

  /// POST /api/me/referrals/payouts/requests
  /// Construye el payload con el shape que espera el backend:
  /// {
  ///   "account_type": "bank|nequi|daviplata|other",
  ///   "data": {
  ///     "account_number": "...",
  ///     "account_kind": "savings|checking", // solo si bank
  ///     "bank_code": "BANCOLOMBIA",         // solo si bank
  ///     "observations": "..."               // opcional
  ///   }
  /// }
  Future<bool> submitPayoutRequest(PayoutRequestInput input) async {
    final uri = Uri.parse(_join('/api/me/referrals/payouts/requests'));

    // Armamos el payload exactamente como lo consume tu ruta
    final Map<String, dynamic> payload = {
      'account_type': input.accountType,
      'data': {
        'account_number': input.accountNumber,
        if (input.accountType.toLowerCase() == 'bank') ...{
          if (input.accountKind != null && input.accountKind!.isNotEmpty)
            'account_kind': input.accountKind,
          if (input.bankCode != null && input.bankCode!.isNotEmpty)
            'bank_code': input.bankCode,
        },
        if (input.observations != null && input.observations!.trim().isNotEmpty)
          'observations': input.observations,
      },
      // Si en el futuro soportas retiros parciales:
      // 'amount_cop': input.amountCop,
    };

    final headers = await _headers();
    final res = await http
        .post(uri, headers: headers, body: json.encode(payload))
        .timeout(_timeout);

    if (kDebugMode) {
      debugPrint('[PayoutsApi.submitPayoutRequest] POST $uri -> ${res.statusCode}');
      debugPrint('[PayoutsApi.submitPayoutRequest] payload: ${json.encode(payload)}');
      debugPrint('[PayoutsApi.submitPayoutRequest] body: ${res.body}');
    }

    // Éxito (incluye 201 Created)
    if (res.statusCode >= 200 && res.statusCode < 300) {
      if (res.body.isEmpty) return true;

      try {
        final body = json.decode(res.body);
        if (body is Map<String, dynamic>) {
          if (body['ok'] == true) return true;
          if (body['request'] is Map) return true;
          if (body['id'] != null || body['request_id'] != null) return true;
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
