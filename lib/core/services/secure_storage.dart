import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SecureStorage {
  // 👇 No puede ser const; debe ser final
  static final FlutterSecureStorage _storage = const FlutterSecureStorage();

  static const _tokenKey = 'access_token';

  static Future<void> saveToken(String token) =>
      _storage.write(key: _tokenKey, value: token);

  static Future<String?> getToken() =>
      _storage.read(key: _tokenKey);

  static Future<void> clear() => _storage.deleteAll();
}
