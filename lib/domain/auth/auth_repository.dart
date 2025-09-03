// lib/domain/auth/auth_repository.dart
import 'package:base_app/data/api/auth_api.dart';
import 'package:base_app/data/session/session_manager.dart';

class AuthRepository {
  final AuthApi api;
  final SessionManager session;

  // Opcional: mantener una copia en memoria del refresh
  String? _refreshToken;

  AuthRepository({required this.api, required this.session});

  Future<void> loginWithPhone({
    required String phone,
    required String password,
  }) async {
    final res = await api.loginWithPhone(phone: phone, password: password);

    // Access token (varios nombres posibles desde backend)
    final access =
        (res['access_token'] ?? res['token'] ?? res['jwt'])?.toString();

    // Refresh token (nuevo desde backend)
    _refreshToken = (res['refresh_token'] ?? res['refreshToken'])?.toString();

    // Id de usuario
    int? userId;
    if (res['user_id'] != null) {
      userId = (res['user_id'] as num).toInt();
    } else if (res['user'] is Map && (res['user']['id'] != null)) {
      userId = (res['user']['id'] as num).toInt();
    }

    // Guarda access + refresh (+ opcionalmente roleId si lo necesitas)
    await session.saveSession(
      token: access,
      refreshToken: _refreshToken,
      userId: userId,
    );
  }

  Future<String?> getStoredToken() => session.getToken();

  /// Intenta renovar el access token usando el refresh guardado.
  /// Devuelve el nuevo access si se pudo, o null si no fue posible.
  Future<String?> refreshAccessTokenIfPossible() async {
    // Lee SIEMPRE desde almacenamiento (para que sobreviva reinicios)
    final rt = await session.getRefreshToken();
    if (rt == null || rt.isEmpty) return null;

    // Mantén la copia en memoria (opcional)
    _refreshToken = rt;

    try {
      final res = await api.refresh(rt);
      final newAccess =
          (res['access_token'] ?? res['token'] ?? res['jwt'])?.toString();

      if (newAccess != null && newAccess.isNotEmpty) {
        // Actualiza solo el access token persistido
        await session.updateAccessToken(newAccess);
        return newAccess;
      }
    } catch (_) {
      // Silencioso: el caller decidirá desloguear o pedir login
    }
    return null;
  }

  // Permite inyectar un refresh externo si hiciera falta (opcional)
  void setRefreshToken(String? token) {
    _refreshToken = token;
  }

  // Recupera el perfil y normaliza el código público de referido
  Future<Map<String, dynamic>?> getProfile() async {
    final token = await session.getToken();
    if (token == null || token.isEmpty) return null;

    final res = await api.me(token); // opcional: api.me() ya no necesita este token

    Map<String, dynamic> asMap(dynamic x) {
      if (x is Map<String, dynamic>) return x;
      if (x is Map) return Map<String, dynamic>.from(x);
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

    final code = (user['public_code'] ??
            user['referral_code'] ??
            user['publicCode'] ??
            user['code'])
        ?.toString();

    return {'public_code': code};
  }

  Future<void> logout() async {
    final access = await session.getToken();
    final rt = await session.getRefreshToken();

    try {
      // Revoca access en backend (silencioso si falla)
      if (access != null && access.isNotEmpty) {
        await api.logout(token: access);
      }
      // Revoca refresh en backend si tienes ese endpoint
      if (rt != null && rt.isNotEmpty) {
        await api.logoutRefresh(refreshToken: rt);
      }
    } catch (_) {
      // ignorar errores de red
    }

    _refreshToken = null;
    await session.clear();
  }
}
