// domain/repositories/user_repository.dart
import '../models/user.dart';

abstract class UserRepository {
  Future<bool> register(User user);
}
