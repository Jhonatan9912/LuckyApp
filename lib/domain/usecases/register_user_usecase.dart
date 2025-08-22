import '../models/user.dart';
import '../repositories/user_repository.dart';

class RegisterUserUseCase {
  final UserRepository repository;

  RegisterUserUseCase(this.repository);

  Future<bool> call(User user) async {
    return await repository.register(user);
  }
}
