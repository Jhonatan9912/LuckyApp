import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../login/login_screen.dart';
import 'widgets/name_input.dart';
// ❌ ya no necesitas importar phone_input.dart aquí (lo usa PhoneWithCountryInput por dentro)
// import 'widgets/phone_input.dart';
import 'widgets/birthdate_input.dart';
import 'widgets/password_input.dart';
import 'widgets/register_button.dart';
import 'widgets/identification_type_input.dart';
import 'widgets/identification_number_input.dart';
import 'widgets/email_input.dart'; // 👈 nuevo
import 'widgets/confirm_password_input.dart'; // 👈 nuevo
import 'widgets/phone_with_country_input.dart'; // 👈 nuevo
import 'package:provider/provider.dart';
import '../../../domain/models/user.dart';
import '../../providers/register_provider.dart';
import 'package:intl/intl.dart';
// imports nuevos arriba:
import 'widgets/referral_checkbox_with_input.dart';
import 'widgets/consent_check_row.dart';
import '../legal/terms_screen.dart';
import '../legal/data_policy_screen.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final nameController = TextEditingController();
  final phoneController = TextEditingController();
  final countryCodeController = TextEditingController(text: '+57');
  final birthDateController = TextEditingController();
  final passwordController = TextEditingController();
  final confirmPasswordController = TextEditingController();
  final emailController = TextEditingController();
  final identificationNumberController = TextEditingController();
  final referralCodeController = TextEditingController();

  bool _submitting = false;
  String? selectedIdType;

  bool _wasReferred = false;
  bool _acceptTerms = false;
  bool _acceptData = false;
  bool get _canSubmit => !_submitting && _acceptTerms && _acceptData;

  bool _isAdult(String birthDateStr) {
    // tu formato actual es 'd/M/yyyy'
    final dt = DateFormat('d/M/yyyy').parseStrict(birthDateStr);
    final now = DateTime.now();

    int age = now.year - dt.year;
    final hadBirthdayThisYear =
        (now.month > dt.month) || (now.month == dt.month && now.day >= dt.day);
    if (!hadBirthdayThisYear) age--;

    return age >= 18;
  }

  @override
  void dispose() {
    nameController.dispose();
    phoneController.dispose();
    countryCodeController.dispose();
    birthDateController.dispose();
    passwordController.dispose();
    confirmPasswordController.dispose();
    emailController.dispose();
    identificationNumberController.dispose();
    referralCodeController.dispose();
    super.dispose();
  }

  void _register() async {
    if (_submitting) return; // evita doble tap

    final name = nameController.text.trim();
    final rawPhone = phoneController.text.trim();
    final phone = rawPhone.replaceAll(RegExp(r'\D'), ''); // solo dígitos

    // normaliza el código de país (permite + y dígitos)
    final rawCode = countryCodeController.text.trim();
    final countryCode = rawCode.replaceAll(RegExp(r'[^0-9+]'), '');

    final birthDate = birthDateController.text.trim();
    final password = passwordController.text.trim();
    final confirmPassword = confirmPasswordController.text.trim();
    final email = emailController.text.trim();
    final idNumber = identificationNumberController.text.trim();

    // Validaciones nuevas
    final emailRegex = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');

    if (name.isEmpty ||
        phone.isEmpty ||
        birthDate.isEmpty ||
        password.isEmpty ||
        confirmPassword.isEmpty ||
        email.isEmpty ||
        idNumber.isEmpty ||
        selectedIdType == null ||
        countryCode.isEmpty) {
      _showMessage('Todos los campos son obligatorios.', isError: true);
      return;
    }

    if (!emailRegex.hasMatch(email)) {
      _showMessage('Correo electrónico no válido.', isError: true);
      return;
    }

    if (password != confirmPassword) {
      _showMessage('Las contraseñas no coinciden.', isError: true);
      return;
    }
    // ❗ Debe ser mayor de edad
    if (!_isAdult(birthDate)) {
      _showMessage('Debes ser mayor de edad (18+).', isError: true);
      return;
    }

    if (!countryCode.startsWith('+')) {
      _showMessage(
        'El código de país debe iniciar con + (ej: +57).',
        isError: true,
      );
      return;
    }
    // ✅ validaciones de consentimientos y referido
    if (!_acceptTerms) {
      _showMessage('Debes aceptar los Términos y Condiciones.', isError: true);
      return;
    }
    if (!_acceptData) {
      _showMessage('Debes aceptar el Tratamiento de Datos.', isError: true);
      return;
    }
if (_wasReferred && referralCodeController.text.trim().isEmpty) {
  _showMessage(
    'Ingresa el código de referido o desmarca la opción.',
    isError: true,
  );
  return;
}


    setState(() => _submitting = true);
    try {
      final provider = Provider.of<RegisterProvider>(context, listen: false);

      final user = User(
        name: name,
        identificationTypeId: int.parse(selectedIdType!),
        identificationNumber: idNumber,
        phone: phone,
        countryCode: countryCode,

        birthdate: DateFormat('d/M/yyyy').parseStrict(birthDate),
        password: password,
        email: email,
        acceptTerms: _acceptTerms, // 👈 NUEVO
        acceptData: _acceptData, // 👈 NUEVO
        referralCode: _wasReferred
            ? referralCodeController.text.trim()
            : null, // 👈 NUEVO (opcional)
      );

      final success = await provider.register(user /*, email: email */);

      if (!success) {
        // 👇 toma el mensaje real que expone el provider (viene del backend)
        final msg =
            provider.errorMessage ??
            'No se pudo registrar. Verifica los datos ingresados.';
        _showMessage(msg, isError: true);
        return;
      }

      // Éxito
      _showMessage('Usuario registrado correctamente.');
      Future.delayed(const Duration(seconds: 2), () {
        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const LoginScreen()),
        );
      });
    } catch (e) {
      _showMessage('Error: ${e.toString()}', isError: true);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _showMessage(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: isError ? Colors.red[700] : Colors.green[700],
        content: Text(msg, style: GoogleFonts.montserrat(color: Colors.white)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text('Registro', style: GoogleFonts.montserrat()),
        backgroundColor: Colors.deepPurple[700],
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            NameInput(controller: nameController),
            const SizedBox(height: 16),

            // ✅ Email como widget
            EmailInput(controller: emailController),
            const SizedBox(height: 16),

            IdentificationTypeInput(
              selectedType: selectedIdType,
              onChanged: (val) => setState(() => selectedIdType = val),
            ),
            const SizedBox(height: 16),

            IdentificationNumberInput(
              controller: identificationNumberController,
            ),
            const SizedBox(height: 16),

            // ✅ Código de país + celular como widget
            PhoneWithCountryInput(
              countryCodeController: countryCodeController,
              phoneController: phoneController,
            ),
            const SizedBox(height: 16),

            BirthDateInput(controller: birthDateController),
            const SizedBox(height: 16),

            PasswordInput(controller: passwordController),
            const SizedBox(height: 16),

            // ✅ Confirmación de contraseña como widget
            ConfirmPasswordInput(controller: confirmPasswordController),
            // ✅ Referido + consentimientos
            const SizedBox(height: 8),
ReferralCheckboxWithInput(
  value: _wasReferred,
  onChanged: (v) => setState(() => _wasReferred = v),
  controller: referralCodeController,
),


            const SizedBox(height: 8),
            ConsentCheckRow(
              value: _acceptTerms,
              onChanged: (v) => setState(() => _acceptTerms = v),
              prefix: 'Acepto los',
              linkText: 'Términos y Condiciones',
              onTapLink: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const TermsScreen()),
                );
              },
            ),
            ConsentCheckRow(
              value: _acceptData,
              onChanged: (v) => setState(() => _acceptData = v),
              prefix: 'Acepto el',
              linkText: 'Tratamiento de Datos',
              onTapLink: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const DataPolicyScreen()),
                );
              },
            ),
            const SizedBox(height: 16),

            RegisterButton(
              onPressed: _canSubmit
                  ? _register
                  : null, // 👈 deshabilita si falta check
            ),
          ],
        ),
      ),
    );
  }
}
