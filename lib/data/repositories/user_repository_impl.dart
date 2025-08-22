// lib/data/repositories/user_repository_impl.dart
import 'package:base_app/data/api/api_service.dart' show ApiService, ApiException;
import 'package:base_app/domain/models/user.dart';
import 'package:base_app/domain/repositories/user_repository.dart';

class UserRepositoryImpl implements UserRepository {
  final ApiService _apiService;

  UserRepositoryImpl(this._apiService);

  @override
  Future<bool> register(User user) async {
    try {
      return await _apiService.registerUser(user); // true en 200/201
    } on ApiException {
      rethrow; // 👈 deja pasar el mensaje real del backend
    } catch (_) {
      throw ApiException('Error inesperado al registrar');
    }
  }
}
