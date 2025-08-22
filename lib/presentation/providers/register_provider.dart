// lib/presentation/providers/register_provider.dart
import 'package:flutter/material.dart';
import 'package:base_app/domain/models/user.dart';
import 'package:base_app/domain/usecases/register_user_usecase.dart';
// Para capturar el mensaje que viene del backend
import 'package:base_app/data/api/api_service.dart' show ApiException;

class RegisterProvider with ChangeNotifier {
  final RegisterUserUseCase registerUserUseCase;

  bool _isLoading = false;
  String? _errorMessage;

  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  RegisterProvider(this.registerUserUseCase);

  Future<bool> register(User user) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final ok = await registerUserUseCase(user); // true en 200/201
      return ok;
    } on ApiException catch (e) {
      // 👇 mensaje textual del backend (ej. "Código de referido inválido")
      _errorMessage = e.message;
      return false;
    } catch (_) {
      _errorMessage = 'Error inesperado al registrar';
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }
}
