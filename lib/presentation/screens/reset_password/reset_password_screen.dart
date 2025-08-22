import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'widgets/code_input.dart';
import 'widgets/send_validate_buttons.dart';
import 'package:base_app/presentation/screens/register/widgets/email_input.dart';

import 'package:base_app/data/api/auth_api.dart';
import 'package:base_app/core/ui/dialogs.dart';
import 'package:base_app/core/validation/validators.dart';

class ResetPasswordScreen extends StatefulWidget {
  const ResetPasswordScreen({super.key});

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final TextEditingController emailController = TextEditingController();
  final TextEditingController codeController = TextEditingController();

  final _api = AuthApi(baseUrl: 'http://10.0.2.2:8000');

  bool codeSent = false;
  bool _loadingSend = false;
  bool _loadingValidate = false;

  @override
  void dispose() {
    emailController.dispose();
    codeController.dispose();
    super.dispose();
  }

  Future<void> _sendCode() async {
    final ctx = context;
    final email = emailController.text.trim();

    // ✅ validación de email
    final err = Validators.email(email);
    if (err != null) {
      if (!ctx.mounted) return;
      await AppDialogs.warning(
        context: ctx,
        title: 'Validación',
        message: err,
      );
      return;
    }

    setState(() => _loadingSend = true);
    FocusScope.of(ctx).unfocus();

    try {
      // 👇 ahora por correo
      await _api.requestPasswordResetByEmail(email: email);
      if (!ctx.mounted) return;

      setState(() => codeSent = true);

      await AppDialogs.success(
        context: ctx,
        title: 'Código enviado',
        message: 'Te enviamos un código al correo ingresado.',
        okText: 'Ingresar código',
      );
    } on AuthException catch (e) {
      if (!ctx.mounted) return;
      await AppDialogs.error(
        context: ctx,
        title: 'No se pudo enviar',
        message: e.message,
      );
    } catch (_) {
      if (!ctx.mounted) return;
      await AppDialogs.error(
        context: ctx,
        title: 'Error',
        message: 'Ocurrió un error inesperado enviando el código.',
      );
    } finally {
      if (mounted) setState(() => _loadingSend = false);
    }
  }

  Future<void> _validateCode() async {
    final ctx = context;
    final navigator = Navigator.of(ctx);
    final email = emailController.text.trim();
    final code = codeController.text.trim();

    // ✅ validaciones locales
    final errEmail = Validators.email(email);
    if (errEmail != null) {
      if (!ctx.mounted) return;
      await AppDialogs.warning(
        context: ctx,
        title: 'Validación',
        message: errEmail,
      );
      return;
    }
    final errCode = Validators.otp(code);
    if (errCode != null) {
      if (!ctx.mounted) return;
      await AppDialogs.warning(
        context: ctx,
        title: 'Validación',
        message: errCode,
      );
      return;
    }

    setState(() => _loadingValidate = true);
    FocusScope.of(ctx).unfocus();

    try {
      // 👇 verifica por correo
      final resetToken = await _api.verifyResetCodeByEmail(email: email, code: code);
      if (!ctx.mounted) return;

      await AppDialogs.success(
        context: ctx,
        title: 'Código verificado',
        message: 'Ahora define tu nueva contraseña.',
        okText: 'Continuar',
      );

      if (!ctx.mounted) return;
      navigator.pushNamed(
        '/nueva-contrasena',
        arguments: {
          'resetToken': resetToken,
          'email': email, // 👈 si quieres mostrarlo o reusar
        },
      );
    } on AuthException catch (e) {
      if (!ctx.mounted) return;
      await AppDialogs.error(
        context: ctx,
        title: 'Código inválido',
        message: e.message,
      );
    } catch (_) {
      if (!ctx.mounted) return;
      await AppDialogs.error(
        context: ctx,
        title: 'Error',
        message: 'Ocurrió un error inesperado validando el código.',
      );
    } finally {
      if (mounted) setState(() => _loadingValidate = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(
          'Restablecer contraseña',
          style: GoogleFonts.montserrat(
            fontWeight: FontWeight.w600,
            fontSize: 18,
          ),
        ),
        backgroundColor: Colors.deepPurple[700],
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Ingresa tu correo electrónico para recibir un código de verificación.',
              style: GoogleFonts.montserrat(fontSize: 16, color: Colors.grey[800]),
            ),
            const SizedBox(height: 24),

            // ✅ Email en vez de teléfono
            EmailInput(controller: emailController),
            const SizedBox(height: 16),

            // Botones enviar/validar
            SendValidateButtons(
              onSend: _loadingSend ? null : _sendCode,
              onValidate: _loadingValidate ? null : _validateCode,
              codeSent: codeSent,
              loadingSend: _loadingSend,
              loadingValidate: _loadingValidate,
            ),

            // Código OTP (solo si ya se envió)
            if (codeSent) ...[
              const SizedBox(height: 16),
              CodeInput(controller: codeController),
            ],
          ],
        ),
      ),
    );
  }
}
