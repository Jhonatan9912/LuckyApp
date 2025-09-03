import 'package:shared_preferences/shared_preferences.dart';

class SessionManager {
  static const _kTokenKey = 'auth_token';
  static const _kRefreshKey = 'auth_refresh_token'; // <-- NUEVO
  static const _kUserIdKey = 'auth_user_id';
  static const _kRoleIdKey = 'auth_role_id';
  static const _kIsPremiumKey = 'is_premium';

  String _normalizeToken(String t) {
    var x = t.trim();
    if (x.toLowerCase().startsWith('bearer ')) {
      x = x.substring(7).trim();
    }
    if (x.length >= 2 && x.startsWith('"') && x.endsWith('"')) {
      x = x.substring(1, x.length - 1).trim();
    }
    return x;
  }

  Future<void> saveSession({
    String? token,
    String? refreshToken,              // <-- NUEVO
    int? userId,
    int? roleId,
  }) async {
    final prefs = await SharedPreferences.getInstance();

    if (token != null) {
      await prefs.setString(_kTokenKey, _normalizeToken(token));
    }

    if (refreshToken != null) {        // <-- NUEVO
      await prefs.setString(_kRefreshKey, _normalizeToken(refreshToken));
    }

    if (userId != null) {
      await prefs.setInt(_kUserIdKey, userId);
    }

    if (roleId != null) {
      await prefs.setInt(_kRoleIdKey, roleId);
    }
  }

  Future<String?> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kTokenKey);
    if (raw == null) return null;
    final t = _normalizeToken(raw);
    return t.isEmpty ? null : t;
  }

  Future<String?> getRefreshToken() async {   // <-- NUEVO
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kRefreshKey);
    if (raw == null) return null;
    final t = _normalizeToken(raw);
    return t.isEmpty ? null : t;
  }

  Future<void> updateAccessToken(String token) async { // <-- NUEVO
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kTokenKey, _normalizeToken(token));
  }

  Future<int?> getUserId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_kUserIdKey);
  }

  Future<int?> getRoleId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_kRoleIdKey);
  }

  /// Lee si el usuario es PRO
  Future<bool?> getIsPremium() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kIsPremiumKey);
  }

  /// Guarda flag PRO
  Future<void> setIsPremium(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kIsPremiumKey, value);
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kTokenKey);
    await prefs.remove(_kRefreshKey);    // <-- NUEVO
    await prefs.remove(_kUserIdKey);
    await prefs.remove(_kRoleIdKey);
    await prefs.remove(_kIsPremiumKey);
  }
}
