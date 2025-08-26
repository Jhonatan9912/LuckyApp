import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../login/login_screen.dart';
import 'package:base_app/data/api/auth_api.dart';
import 'package:base_app/core/ui/dialogs.dart';
import 'package:base_app/core/validation/validators.dart';
import 'package:base_app/core/config/env.dart';

class SetNewPasswordScreen extends StatefulWidget {
  const SetNewPasswordScreen({super.key});

  @override
  State<SetNewPasswordScreen> createState() => _SetNewPasswordScreenState();
}

class _SetNewPasswordScreenState extends State<SetNewPasswordScreen> {
  final TextEditingController passwordController = TextEditingController();
  final TextEditingController confirmPasswordController =
      TextEditingController();

  bool showPassword = false;
  bool showConfirmPassword = false;
  bool _loading = false;

  // Api
  final _api = AuthApi(baseUrl: Env.apiBaseUrl);

  String? _resetToken; // viene desde ResetPasswordScreen
  String? _phone; // opcional, por si quieres mostrarlo en UI

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Recibe argumentos: {'resetToken': ..., 'phone': ...}
    final args = ModalRoute.of(context)?.settings.arguments;
    if (args is Map) {
      _resetToken = args['resetToken']?.toString();
      _phone = args['phone']?.toString();
    }
  }

  @override
  void dispose() {
    passwordController.dispose();
    confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final navigator = Navigator.of(context); // ✅ solo capturamos el navigator

    final password = passwordController.text.trim();
    final confirm = confirmPasswordController.text.trim();

    // Validaciones locales (sin await)
    final errPwd = Validators.password(password);
    if (errPwd != null) {
      await AppDialogs.warning(
        context: context,
        title: 'Validación',
        message: errPwd,
      );
      return;
    }
    if (password != confirm) {
      await AppDialogs.warning(
        context: context,
        title: 'Validación',
        message: 'Las contraseñas no coinciden.',
      );
      return;
    }
    if (_resetToken == null || _resetToken!.isEmpty) {
      await AppDialogs.error(
        context: context,
        title: 'Error',
        message:
            'No se encontró el token de restablecimiento. Vuelve a solicitar el código.',
      );
      return;
    }

    setState(() => _loading = true);
    FocusScope.of(context).unfocus();

    try {
      await _api.confirmPasswordReset(
        resetToken: _resetToken!,
        newPassword: password,
      );

      if (!mounted) return; // ✅ guarda antes de usar context tras await
      await AppDialogs.success(
        context: context,
        title: '¡Listo!',
        message: 'Tu contraseña se actualizó correctamente.',
        okText: 'Iniciar sesión',
      );

      if (!mounted) return; // ✅ otra guarda
      navigator.pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (_) => false,
      );
    } on AuthException catch (e) {
      if (!mounted) return; // ✅ guarda
      await AppDialogs.error(
        context: context,
        title: 'No se pudo actualizar',
        message: e.message,
      );
    } catch (_) {
      if (!mounted) return; // ✅ guarda
      await AppDialogs.error(
        context: context,
        title: 'Error',
        message: 'Ocurrió un error inesperado al actualizar la contraseña.',
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hint = _phone != null
        ? 'Definir nueva contraseña para $_phone'
        : 'Define tu nueva contraseña';

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(
          'Nueva contraseña',
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
              hint,
              style: GoogleFonts.montserrat(
                fontSize: 14,
                color: Colors.grey[700],
              ),
            ),
            const SizedBox(height: 16),

            // Nueva contraseña
            TextField(
              controller: passwordController,
              obscureText: !showPassword,
              style: GoogleFonts.montserrat(),
              decoration: InputDecoration(
                labelText: 'Nueva contraseña',
                labelStyle: GoogleFonts.montserrat(),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                suffixIcon: IconButton(
                  icon: Icon(
                    showPassword ? Icons.visibility : Icons.visibility_off,
                    color: Colors.grey[700],
                  ),
                  onPressed: () => setState(() => showPassword = !showPassword),
                ),
              ),
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 16),

            // Confirmar contraseña
            TextField(
              controller: confirmPasswordController,
              obscureText: !showConfirmPassword,
              style: GoogleFonts.montserrat(),
              decoration: InputDecoration(
                labelText: 'Confirmar contraseña',
                labelStyle: GoogleFonts.montserrat(),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                suffixIcon: IconButton(
                  icon: Icon(
                    showConfirmPassword
                        ? Icons.visibility
                        : Icons.visibility_off,
                    color: Colors.grey[700],
                  ),
                  onPressed: () => setState(
                    () => showConfirmPassword = !showConfirmPassword,
                  ),
                ),
              ),
              onSubmitted: (_) {
                if (!_loading) _submit();
              },
            ),

            const SizedBox(height: 24),

            // Botón
            ElevatedButton(
              onPressed: _loading ? null : _submit,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.amber[800],
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(30),
                ),
              ),
              child: _loading
                  ? const SizedBox(
                      height: 22,
                      width: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(
                      'Restablecer contraseña',
                      style: GoogleFonts.montserrat(
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
