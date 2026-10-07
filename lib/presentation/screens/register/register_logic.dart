// lib/presentation/screens/register/register_logic.dart
//
// Validación y envío del registro, compartidos entre la app móvil y la web.
import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../domain/models/user.dart';
import '../../providers/register_provider.dart';

class RegisterFormData {
  final String name;
  final String phone; // solo dígitos
  final String countryCode;
  final String birthDate; // formato d/M/yyyy
  final String password;
  final String confirmPassword;
  final String email;
  final String idNumber;
  final String? idType;
  final bool wasReferred;
  final String referralCode;
  final bool acceptTerms;
  final bool acceptData;

  RegisterFormData({
    required String name,
    required String rawPhone,
    required String rawCountryCode,
    required String birthDate,
    required String password,
    required String confirmPassword,
    required String email,
    required String idNumber,
    required this.idType,
    required this.wasReferred,
    required String referralCode,
    required this.acceptTerms,
    required this.acceptData,
  }) : name = name.trim(),
       phone = rawPhone.trim().replaceAll(RegExp(r'\D'), ''),
       countryCode = rawCountryCode.trim().replaceAll(RegExp(r'[^0-9+]'), ''),
       birthDate = birthDate.trim(),
       password = password.trim(),
       confirmPassword = confirmPassword.trim(),
       email = email.trim(),
       idNumber = idNumber.trim(),
       referralCode = referralCode.trim();

  static bool _isAdult(String birthDateStr) {
    final dt = DateFormat('d/M/yyyy').parseStrict(birthDateStr);
    final now = DateTime.now();
    int age = now.year - dt.year;
    final hadBirthdayThisYear =
        (now.month > dt.month) || (now.month == dt.month && now.day >= dt.day);
    if (!hadBirthdayThisYear) age--;
    return age >= 18;
  }

  /// Devuelve el mensaje de error, o null si el formulario es válido.
  String? validate() {
    final emailRegex = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');

    if (name.isEmpty ||
        phone.isEmpty ||
        birthDate.isEmpty ||
        password.isEmpty ||
        confirmPassword.isEmpty ||
        email.isEmpty ||
        idNumber.isEmpty ||
        idType == null ||
        countryCode.isEmpty) {
      return 'Todos los campos son obligatorios.';
    }
    if (!emailRegex.hasMatch(email)) return 'Correo electrónico no válido.';
    if (password != confirmPassword) return 'Las contraseñas no coinciden.';
    if (!_isAdult(birthDate)) return 'Debes ser mayor de edad (18+).';
    if (!countryCode.startsWith('+')) {
      return 'El código de país debe iniciar con + (ej: +57).';
    }
    if (!acceptTerms) return 'Debes aceptar los Términos y Condiciones.';
    if (!acceptData) return 'Debes aceptar el Tratamiento de Datos.';
    if (wasReferred && referralCode.isEmpty) {
      return 'Ingresa el código de referido o desmarca la opción.';
    }
    return null;
  }

  User toUser() => User(
    name: name,
    identificationTypeId: int.parse(idType!),
    identificationNumber: idNumber,
    phone: phone,
    countryCode: countryCode,
    birthdate: DateFormat('d/M/yyyy').parseStrict(birthDate),
    password: password,
    email: email,
    acceptTerms: acceptTerms,
    acceptData: acceptData,
    referralCode: wasReferred ? referralCode : null,
  );
}

/// Envía el registro al backend. Devuelve el mensaje de error, o null si fue exitoso.
Future<String?> submitRegistration(
  BuildContext context,
  RegisterFormData data,
) async {
  final provider = Provider.of<RegisterProvider>(context, listen: false);
  final success = await provider.register(data.toUser());
  if (!success) {
    return provider.errorMessage ??
        'No se pudo registrar. Verifica los datos ingresados.';
  }
  return null;
}
