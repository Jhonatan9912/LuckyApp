// lib/data/api/account_api.dart
//
// API de la cuenta propia: eliminación de cuenta y datos (Habeas Data).
import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'package:base_app/core/config/env.dart';
import 'package:base_app/data/session/session_manager.dart';

/// Resultado del intento de eliminar la cuenta.
class DeleteAccountResult {
  final bool ok;
  final String? code; // BAD_PASSWORD | PENDING_COMMISSIONS | ACTIVE_SUBSCRIPTION | ...
  final String message;

  DeleteAccountResult({required this.ok, this.code, required this.message});
}

class AccountApi {
  final String baseUrl;
  final SessionManager session;

  AccountApi({String? baseUrl, SessionManager? session})
      : baseUrl = baseUrl ?? Env.apiBaseUrl,
        session = session ?? SessionManager();

  static const _timeout = Duration(seconds: 20);

  String _join(String path) {
    final b = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    return '$b$path';
  }

  /// DELETE /api/me/account  — elimina (anonimiza) la cuenta del usuario.
  /// Requiere la contraseña actual como confirmación.
  Future<DeleteAccountResult> deleteMyAccount({required String password}) async {
    final token = await session.getToken();
    final uri = Uri.parse(_join('/api/me/account'));
    final res = await http
        .delete(
          uri,
          headers: {
            'Accept': 'application/json',
            'Content-Type': 'application/json',
            if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
          },
          body: jsonEncode({'password': password}),
        )
        .timeout(_timeout);

    Map<String, dynamic> body = {};
    try {
      body = jsonDecode(res.body) as Map<String, dynamic>;
    } catch (_) {}

    if (res.statusCode == 200 && (body['ok'] == true)) {
      return DeleteAccountResult(
        ok: true,
        message: (body['message'] ?? 'Tu cuenta fue eliminada.').toString(),
      );
    }

    return DeleteAccountResult(
      ok: false,
      code: body['code']?.toString(),
      message: (body['message'] ?? body['error'] ?? 'No se pudo eliminar la cuenta.')
          .toString(),
    );
  }
}
