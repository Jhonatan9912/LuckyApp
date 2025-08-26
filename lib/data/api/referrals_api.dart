// lib/data/api/referrals_api.dart
import 'dart:convert';
import 'package:http/http.dart' as http;

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
        id: j['id'] as int,
        referredUserId: j['referred_user_id'] as int?,
        referredName: j['referred_name'] as String?,
        referredEmail: j['referred_email'] as String?,
        status: (j['status'] ?? '').toString(),
        createdAt: (j['created_at'] is String)
            ? DateTime.tryParse(j['created_at'])
            : null,
        proActive: (j['pro_active'] ?? false) == true,
      );
}

class ReferralSummary {
  final int total;
  final int activos;
  final int inactivos;

  ReferralSummary({
    required this.total,
    required this.activos,
    required this.inactivos,
  });

  factory ReferralSummary.fromJson(Map<String, dynamic> j) => ReferralSummary(
        total: j['total'] ?? 0,
        activos: j['activos'] ?? 0,
        inactivos: j['inactivos'] ?? 0,
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

class ReferralsApi {
  final String baseUrl;
  final SessionManager session;

  ReferralsApi({
    required this.baseUrl,
    required this.session,
  });

  Future<ReferralSummary> fetchSummary() async {
    final token = await session.getToken();
    final uri = Uri.parse('$baseUrl/api/me/referrals/summary');

    final res = await http.get(
      uri,
      headers: {
        'Authorization': 'Bearer $token',
        'Accept': 'application/json',
        'Content-Type': 'application/json',
      },
    );

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
    final uri = Uri.parse('$baseUrl/api/me/referrals?limit=$limit&offset=$offset');

    final res = await http.get(
      uri,
      headers: {
        'Authorization': 'Bearer $token',
        'Accept': 'application/json',
        'Content-Type': 'application/json',
      },
    );

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

  /// Nuevo: totales de comisiones (para el banner de “Comisión disponible”)
  Future<PayoutsSummary> fetchPayoutsSummary({String currency = 'COP'}) async {
    final token = await session.getToken();
    final uri = Uri.parse(
      '$baseUrl/api/me/referrals/payouts/summary?currency=${Uri.encodeComponent(currency)}',
    );

    final res = await http.get(
      uri,
      headers: {
        'Authorization': 'Bearer $token',
        'Accept': 'application/json',
        'Content-Type': 'application/json',
      },
    );

    if (res.statusCode >= 200 && res.statusCode < 300) {
      final Map<String, dynamic> data = json.decode(res.body);
      return PayoutsSummary.fromJson(data);
    }

    throw Exception(
      'Error ${res.statusCode} al obtener payouts summary: ${res.body}',
    );
  }
}

// Helper para crear la API con tus singletons actuales
ReferralsApi buildReferralsApi() {
  return ReferralsApi(
    baseUrl: Env.apiBaseUrl,
    session: SessionManager(),
  );
}
