import 'package:flutter/material.dart';
import 'package:base_app/core/ui/dialogs.dart' show AppSnackBars;
import 'package:google_fonts/google_fonts.dart';
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
import 'register_logic.dart';
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

    final data = RegisterFormData(
      name: nameController.text,
      rawPhone: phoneController.text,
      rawCountryCode: countryCodeController.text,
      birthDate: birthDateController.text,
      password: passwordController.text,
      confirmPassword: confirmPasswordController.text,
      email: emailController.text,
      idNumber: identificationNumberController.text,
      idType: selectedIdType,
      wasReferred: _wasReferred,
      referralCode: referralCodeController.text,
      acceptTerms: _acceptTerms,
      acceptData: _acceptData,
    );

    final invalid = data.validate();
    if (invalid != null) {
      _showMessage(invalid, isError: true);
      return;
    }

    setState(() => _submitting = true);
    try {
      final error = await submitRegistration(context, data);
      if (error != null) {
        _showMessage(error, isError: true);
        return;
      }

      // Éxito
      _showMessage('Usuario registrado correctamente.');
      Future.delayed(const Duration(seconds: 2), () {
        if (!mounted) return;
        Navigator.pushReplacementNamed(context, '/login');
      });
    } catch (e) {
      _showMessage('Error: ${e.toString()}', isError: true);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _showMessage(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showAppSnackBar(
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
