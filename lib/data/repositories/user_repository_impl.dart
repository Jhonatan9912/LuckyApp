import 'package:base_app/data/api/api_service.dart'; // 👈 sin "show"
import 'package:base_app/domain/models/user.dart';
import 'package:base_app/domain/repositories/user_repository.dart';

class UserRepositoryImpl implements UserRepository {
  final ApiService _api;

  // Permite inyectar ApiService, o crea uno con Env.apiBaseUrl por defecto
  UserRepositoryImpl({ApiService? api}) : _api = api ?? ApiService();

  @override
  Future<bool> register(User user) async {
    try {
      // Ajusta el endpoint si en tu backend es otro (por ejemplo /api/users)
      final res = await _api.post('/api/auth/register', body: user.toJson());
      // Si tu API devuelve { ok: true, ... }
      if (res is Map<String, dynamic> && res['ok'] == true) return true;
      // Si llega aquí, la API respondió 2xx pero sin ok:true
      throw ApiException(500, 'Respuesta inválida del servidor');
    } on ApiException {
      rethrow; // deja pasar el detalle (status y body) del backend
    } catch (_) {
      throw ApiException(500, 'Error inesperado al registrar'); // 👈 requiere (code, body)
    }
  }
}
