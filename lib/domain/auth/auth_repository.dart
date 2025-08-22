// lib/domain/auth/auth_repository.dart
import 'package:base_app/data/api/auth_api.dart';
import 'package:base_app/data/session/session_manager.dart';

class AuthRepository {
  final AuthApi api;
  final SessionManager session;
  AuthRepository({required this.api, required this.session});

  Future<void> loginWithPhone({
    required String phone,
    required String password,
  }) async {
    final res = await api.loginWithPhone(phone: phone, password: password);
    final token = (res['token'] ?? res['access_token'] ?? res['jwt'])
        ?.toString();

    int? userId;
    if (res['user_id'] != null) {
      userId = (res['user_id'] as num).toInt();
    } else if (res['user'] is Map && (res['user']['id'] != null)) {
      userId = (res['user']['id'] as num).toInt();
    }
    await session.saveSession(token: token, userId: userId);
  }

  Future<String?> getStoredToken() => session.getToken();

  // Recupera el perfil y normaliza el código público de referido
  Future<Map<String, dynamic>?> getProfile() async {
    final token = await session.getToken();
    if (token == null || token.isEmpty) return null;

    final res = await api.me(token);

    // ✅ renombrado (sin underscore) y con cast seguro
    Map<String, dynamic> asMap(dynamic x) {
      if (x is Map<String, dynamic>) return x;
      if (x is Map) return Map<String, dynamic>.from(x); // 👈 sin cast
      return <String, dynamic>{};
    }

    final root = asMap(res);
    Map<String, dynamic> user;

    if (root['data'] is Map && (root['data']['user'] is Map)) {
      user = asMap(root['data']['user']);
    } else if (root['data'] is Map) {
      user = asMap(root['data']);
    } else if (root['user'] is Map) {
      user = asMap(root['user']);
    } else {
      user = root;
    }

    final code =
        (user['public_code'] ??
                user['referral_code'] ??
                user['publicCode'] ??
                user['code'])
            ?.toString();

    return {'public_code': code};
  }

  Future<void> logout() async {
    final token = await session.getToken();
    if (token != null && token.isNotEmpty) {
      try {
        await api.logout(token: token);
      } catch (_) {}
    }
    await session.clear();
  }
}
