import 'package:shared_preferences/shared_preferences.dart';

class SessionManager {
  static const _kTokenKey = 'auth_token';
  static const _kUserIdKey = 'auth_user_id';
  static const _kRoleIdKey = 'auth_role_id'; // 👈 nueva clave

  Future<void> saveSession({String? token, int? userId, int? roleId}) async {
    final prefs = await SharedPreferences.getInstance();
    if (token != null) {
      var t = token.trim();
      if (t.toLowerCase().startsWith('bearer ')) t = t.substring(7).trim();
      if (t.length >= 2 && t.startsWith('"') && t.endsWith('"')) {
        t = t.substring(1, t.length - 1).trim();
      }
      await prefs.setString(_kTokenKey, t);
    }
    if (userId != null) await prefs.setInt(_kUserIdKey, userId);
    if (roleId != null) await prefs.setInt(_kRoleIdKey, roleId); // 👈 guardar rol
  }

  Future<String?> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kTokenKey);
    if (raw == null) return null;
    var t = raw.trim();
    if (t.toLowerCase().startsWith('bearer ')) t = t.substring(7).trim();
    if (t.length >= 2 && t.startsWith('"') && t.endsWith('"')) {
      t = t.substring(1, t.length - 1).trim();
    }
    return t.isEmpty ? null : t;
  }

  Future<int?> getUserId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_kUserIdKey);
  }

  Future<int?> getRoleId() async { // 👈 leer rol
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_kRoleIdKey);
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kTokenKey);
    await prefs.remove(_kUserIdKey);
    await prefs.remove(_kRoleIdKey); // 👈 limpiar rol
  }
}
