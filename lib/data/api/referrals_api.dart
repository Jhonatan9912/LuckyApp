// lib/data/api/referrals_api.dart
import 'dart:convert';
import 'dart:async';
import 'package:http/http.dart' as http;

// 👇 agrega esto para poder usar debugPrint
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
    referredEmail:
        j['referred_email'] as String? ?? j['referredEmail'] as String?,
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

  // 👇 NUEVO: campos que manda el backend y tu UI debe usar
  final double availableCop;
  final double pendingCop;
  final double paidCop;
  final double totalCop;

  // NUEVO: “En retiro / En proceso”
  final double inWithdrawalCop;

  // (Opcional) si quieres tener también micros:
  final int availableMicros;
  final int pendingMicros;
  final int paidMicros;
  final int totalMicros;
  final int inWithdrawalMicros;

  ReferralSummary({
    required this.total,
    required this.activos,
    required this.inactivos,
    required this.availableCop,
    required this.pendingCop,
    required this.paidCop,
    required this.totalCop,
    this.availableMicros = 0,
    this.pendingMicros = 0,
    this.paidMicros = 0,
    this.totalMicros = 0,
    this.inWithdrawalCop = 0.0, // <-- NUEVO
    this.inWithdrawalMicros = 0, // <-- NUEVO
  });

  factory ReferralSummary.fromJson(Map<String, dynamic> j) => ReferralSummary(
    total: (j['total'] ?? 0) as int,
    activos: (j['activos'] ?? 0) as int,
    inactivos: (j['inactivos'] ?? 0) as int,

    // 👇 leer doubles de forma segura
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

    // NUEVO: “En retiro” (acepta snake_case o camelCase)
    inWithdrawalCop: (j['in_withdrawal_cop'] is num)
        ? (j['in_withdrawal_cop'] as num).toDouble()
        : (j['inWithdrawalCop'] is num)
            ? (j['inWithdrawalCop'] as num).toDouble()
            : double.tryParse('${j['in_withdrawal_cop'] ?? j['inWithdrawalCop']}') ?? 0.0,

    // micros (opcionales)
    availableMicros: (j['available_micros'] ?? 0) as int,
    pendingMicros: (j['pending_micros'] ?? 0) as int,
    paidMicros: (j['paid_micros'] ?? 0) as int,
    totalMicros: (j['total_micros'] ?? 0) as int,
    inWithdrawalMicros: (j['in_withdrawal_micros'] ?? j['inWithdrawalMicros'] ?? 0) as int,
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

  Future<ReferralSummary> fetchSummary() async {
    final token = await session.getToken();
    final uri = Uri.parse('$baseUrl/api/me/referrals/summary');

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
    // 👇 importante: con slash al final
    final uri = Uri.parse(
      '$baseUrl/api/me/referrals/?limit=$limit&offset=$offset',
    );

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
      final List<dynamic> data = json.decode(res.body);
      return data
          .map((e) => ReferralItem.fromJson(e as Map<String, dynamic>))
          .toList();
    }

    throw Exception(
      'Error ${res.statusCode} al obtener la lista de referidos: ${res.body}',
    );
  }

  Future<PayoutsSummary> fetchPayoutsSummary({String currency = 'COP'}) async {
    final token = await session.getToken(); // puede ser null

    // Construye la URL usando baseUrl inyectado
    final uri = Uri.parse(
      '$baseUrl/api/me/referrals/payouts/summary?currency=${Uri.encodeComponent(currency)}',
    );

    // Logs seguros (no crashean si token es null)
    final safeTokenHead = (token == null)
        ? 'null'
        : (token.length > 12 ? token.substring(0, 12) : token);
    debugPrint('[referrals_api] baseUrl=$baseUrl');
    debugPrint('[referrals_api] token(head)=$safeTokenHead...');

    final res = await http
        .get(
          uri,
          headers: {
            'Authorization': 'Bearer ${token ?? ''}', // si es null, manda vacío
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
}

// Helper para instanciar usando tus singletons actuales
ReferralsApi buildReferralsApi() {
  return ReferralsApi(
    baseUrl: Env.apiBaseUrl, // asegúrate que no termine en "/"
    session: SessionManager(),
  );
}
