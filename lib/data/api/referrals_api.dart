// lib/data/api/referrals_api.dart
import 'dart:convert';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart' show debugPrint;

import 'package:base_app/core/config/env.dart';
import 'package:base_app/data/session/session_manager.dart';

class ReferralItem {
  final int id;
  final int? referredUserId;
  final String? referredName;
  final String? referredEmail;
  final String status;
  final DateTime? createdAt;
  final bool proActive;

  ReferralItem({
    required this.id,
    required this.status,
    this.referredUserId,
    this.referredName,
    this.referredEmail,
    this.createdAt,
    this.proActive = false,
  });

  factory ReferralItem.fromJson(Map<String, dynamic> j) => ReferralItem(
        id: (j['id'] ?? 0) as int,
        referredUserId: (j['referred_user_id'] ?? j['referredUserId']) as int?,
        referredName: j['referred_name'] as String? ?? j['referredName'] as String?,
        referredEmail: j['referred_email'] as String? ?? j['referredEmail'] as String?,
        status: (j['status'] ?? '').toString(),
        createdAt: j['created_at'] != null
            ? DateTime.tryParse(j['created_at'])
            : (j['createdAt'] != null ? DateTime.tryParse(j['createdAt']) : null),
        proActive: (j['pro_active'] ?? j['proActive'] ?? false) == true,
      );
}

class ReferralSummary {
  final int total;
  final int activos;
  final int inactivos;

  // Saldos operativos
  final double availableCop;
  final double pendingCop;
  final double inWithdrawalCop;
  final double paidCop;
  final double totalCop;

  // Micros (opcionales)
  final int availableMicros;
  final int pendingMicros;
  final int inWithdrawalMicros;
  final int paidMicros;
  final int totalMicros;

  // Moneda (opcional)
  final String? currency;

  ReferralSummary({
    required this.total,
    required this.activos,
    required this.inactivos,
    required this.availableCop,
    required this.pendingCop,
    required this.inWithdrawalCop,
    required this.paidCop,
    required this.totalCop,
    this.availableMicros = 0,
    this.pendingMicros = 0,
    this.inWithdrawalMicros = 0,
    this.paidMicros = 0,
    this.totalMicros = 0,
    this.currency,
  });

  factory ReferralSummary.fromJson(Map<String, dynamic> j) => ReferralSummary(
        total: (j['total'] ?? 0) as int,
        activos: (j['activos'] ?? 0) as int,
        inactivos: (j['inactivos'] ?? 0) as int,

        // doubles seguros
        availableCop: (j['available_cop'] is num)
            ? (j['available_cop'] as num).toDouble()
            : double.tryParse('${j['available_cop']}') ?? 0.0,
        pendingCop: (j['pending_cop'] is num)
            ? (j['pending_cop'] as num).toDouble()
            : double.tryParse('${j['pending_cop']}') ?? 0.0,
        paidCop: (j['paid_cop'] is num)
            ? (j['paid_cop'] as num).toDouble()
            : double.tryParse('${j['paid_cop']}') ?? 0.0,
        totalCop: (j['total_cop'] is num)
            ? (j['total_cop'] as num).toDouble()
            : double.tryParse('${j['total_cop']}') ?? 0.0,

        // en retiro (acepta snake/camel)
        inWithdrawalCop: (j['in_withdrawal_cop'] is num)
            ? (j['in_withdrawal_cop'] as num).toDouble()
            : (j['inWithdrawalCop'] is num)
                ? (j['inWithdrawalCop'] as num).toDouble()
                : double.tryParse('${j['in_withdrawal_cop'] ?? j['inWithdrawalCop']}') ?? 0.0,

        // micros opcionales
        availableMicros: (j['available_micros'] ?? 0) as int,
        pendingMicros: (j['pending_micros'] ?? 0) as int,
        inWithdrawalMicros: (j['in_withdrawal_micros'] ?? j['inWithdrawalMicros'] ?? 0) as int,
        paidMicros: (j['paid_micros'] ?? 0) as int,
        totalMicros: (j['total_micros'] ?? 0) as int,

        currency: j['currency']?.toString(),
      );
}

class PayoutsSummary {
  final String currency;
  final double pending;
  final double paid;

  PayoutsSummary({
    required this.currency,
    required this.pending,
    required this.paid,
  });

  factory PayoutsSummary.fromJson(Map<String, dynamic> j) => PayoutsSummary(
        currency: (j['currency'] ?? 'COP').toString(),
        pending: (j['pending'] is num)
            ? (j['pending'] as num).toDouble()
            : double.tryParse('${j['pending']}') ?? 0.0,
        paid: (j['paid'] is num)
            ? (j['paid'] as num).toDouble()
            : double.tryParse('${j['paid']}') ?? 0.0,
      );
}

// -------------------- API --------------------
class ReferralsApi {
  final String baseUrl;
  final SessionManager session;

  ReferralsApi({required this.baseUrl, required this.session});

  static const _timeout = Duration(seconds: 15);

  String _join(String path) {
    if (baseUrl.endsWith('/')) {
      return '${baseUrl.substring(0, baseUrl.length - 1)}$path';
    }
    return '$baseUrl$path';
  }

  Future<ReferralSummary> fetchSummary() async {
    final token = await session.getToken();
    final uri = Uri.parse(_join('/api/me/referrals/summary'));

    final res = await http
        .get(
          uri,
          headers: {
            'Authorization': 'Bearer $token',
            'Accept': 'application/json',
            'Content-Type': 'application/json',
          },
        )
        .timeout(_timeout);

    debugPrint('[referrals_api] GET $uri -> ${res.statusCode}');
    debugPrint('[referrals_api] body: ${res.body}');

    if (res.statusCode >= 200 && res.statusCode < 300) {
      final Map<String, dynamic> data = json.decode(res.body);
      return ReferralSummary.fromJson(data);
    }

    throw Exception(
      'Error ${res.statusCode} al obtener summary de referidos: ${res.body}',
    );
  }

  Future<List<ReferralItem>> fetchList({int limit = 50, int offset = 0}) async {
    final token = await session.getToken();
    final uri = Uri.parse(_join('/api/me/referrals/?limit=$limit&offset=$offset'));

    final res = await http
        .get(
          uri,
          headers: {
            'Authorization': 'Bearer $token',
            'Accept': 'application/json',
            'Content-Type': 'application/json',
          },
        )
        .timeout(_timeout);

    debugPrint('[referrals_api] GET $uri -> ${res.statusCode}');
    debugPrint('[referrals_api] body: ${res.body}');

    if (res.statusCode >= 200 && res.statusCode < 300) {
      final decoded = json.decode(res.body);
      if (decoded is List) {
        return decoded
            .map((e) => ReferralItem.fromJson(e as Map<String, dynamic>))
            .toList();
      }
      if (decoded is Map && decoded['items'] is List) {
        return (decoded['items'] as List)
            .map((e) => ReferralItem.fromJson(e as Map<String, dynamic>))
            .toList();
      }
      return const <ReferralItem>[];
    }

    throw Exception(
      'Error ${res.statusCode} al obtener la lista de referidos: ${res.body}',
    );
  }

  Future<PayoutsSummary> fetchPayoutsSummary({String currency = 'COP'}) async {
    final token = await session.getToken();
    final uri = Uri.parse(
      _join('/api/me/referrals/payouts/summary?currency=${Uri.encodeComponent(currency)}'),
    );

    final safeTokenHead = (token == null)
        ? 'null'
        : (token.length > 12 ? token.substring(0, 12) : token);
    debugPrint('[referrals_api] baseUrl=$baseUrl');
    debugPrint('[referrals_api] token(head)=$safeTokenHead...');

    final res = await http
        .get(
          uri,
          headers: {
            'Authorization': 'Bearer ${token ?? ''}',
            'Accept': 'application/json',
            'Content-Type': 'application/json',
          },
        )
        .timeout(_timeout);

    debugPrint('[referrals_api] GET $uri -> ${res.statusCode}');
    debugPrint('[referrals_api] body: ${res.body}');

    if (res.statusCode >= 200 && res.statusCode < 300) {
      final Map<String, dynamic> data = json.decode(res.body);
      return PayoutsSummary.fromJson(data);
    }

    throw Exception(
      'Error ${res.statusCode} al obtener payouts summary: ${res.body}',
    );
  }

  /// Crea una solicitud de retiro.
  /// El backend debe:
  /// - Descontar atómicamente `amount_cop` de disponible.
  /// - Aumentar `in_withdrawal`.
  /// - Responder 200/201 con el request creado (o 204).
  Future<void> createPayoutRequest({
    required double amountCop,
    required String accountType,              // 'bank' | 'nequi' | 'daviplata' | 'other'
    required Map<String, dynamic> payoutData, // {bank_code?, account_kind?, account_number, observations?}
  }) async {
    final token = await session.getToken();
    final uri = Uri.parse(_join('/api/me/referrals/payouts/requests'));

    final payload = <String, dynamic>{
      'amount_cop': amountCop,     // si tu backend usa micros, cámbialo por amount_micros
      'account_type': accountType, // 'bank'|'nequi'|'daviplata'|'other'
      'data': {
        // Campos opcionales según el tipo:
        if (payoutData['bank_code'] != null) 'bank_code': payoutData['bank_code'],
        if (payoutData['account_kind'] != null) 'account_kind': payoutData['account_kind'], // 'savings'|'checking'
        'account_number': payoutData['account_number'],
        if (payoutData['observations'] != null && '${payoutData['observations']}'.trim().isNotEmpty)
          'observations': payoutData['observations'],
      },
    };

    debugPrint('[referrals_api] POST $uri payload=${json.encode(payload)}');

    final res = await http
        .post(
          uri,
          headers: {
            'Authorization': 'Bearer $token',
            'Accept': 'application/json',
            'Content-Type': 'application/json',
          },
          body: json.encode(payload),
        )
        .timeout(_timeout);

    debugPrint('[referrals_api] POST $uri -> ${res.statusCode}');
    debugPrint('[referrals_api] body: ${res.body}');

    if (res.statusCode >= 200 && res.statusCode < 300) {
      return; // OK
    }

    throw Exception(
      'Error ${res.statusCode} al crear solicitud de retiro: ${res.body}',
    );
  }
}

// Helper para instanciar usando tus singletons actuales
ReferralsApi buildReferralsApi() {
  return ReferralsApi(
    baseUrl: Env.apiBaseUrl, // asegúrate que no termine en "/"
    session: SessionManager(),
  );
}
