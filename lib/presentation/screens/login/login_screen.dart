import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'widgets/phone_input.dart';
import 'widgets/password_input.dart';
import 'widgets/login_button.dart';
import 'widgets/forgot_password_button.dart';
import 'package:base_app/data/api/auth_api.dart';
import 'package:base_app/core/services/secure_storage.dart';
import 'package:base_app/core/ui/dialogs.dart';
import 'package:base_app/data/session/session_manager.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController phoneController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  bool obscureText = true;
  bool _loading = false;

  final _authApi = AuthApi(baseUrl: 'http://10.0.2.2:8000');
  final _session = SessionManager();

  @override
  void dispose() {
    phoneController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(height: 50),
                Text(
                  '¡Bienvenido!',
                  style: GoogleFonts.montserrat(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    color: Colors.amber[800],
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'Tu suerte comienza aquí 🔢💰',
                  style: GoogleFonts.montserrat(
                    fontSize: 16,
                    color: Colors.deepPurple[700],
                  ),
                ),
                const SizedBox(height: 40),

                PhoneInput(controller: phoneController),
                const SizedBox(height: 20),

                PasswordInput(
                  controller: passwordController,
                  obscureText: obscureText,
                  toggleVisibility: () {
                    setState(() => obscureText = !obscureText);
                  },
                ),

                const ForgotPasswordButton(),

                const SizedBox(height: 20),

                Opacity(
                  opacity: _loading ? 0.6 : 1,
                  child: AbsorbPointer(
                    absorbing: _loading,
                    child: LoginButton(
                      onPressed: () async {
                        final phone = phoneController.text.trim();
                        final pass = passwordController.text;
                        final ctx = context;
                        final navigator = Navigator.of(ctx);

                        FocusScope.of(ctx).unfocus();

                        if (phone.isEmpty || pass.isEmpty) {
                          if (!ctx.mounted) return;
                          await AppDialogs.warning(
                            context: ctx,
                            title: 'Validación',
                            message: 'Ingresa tu teléfono y contraseña.',
                          );
                          return;
                        }

                        setState(() => _loading = true);
                        try {
                          // 1) Llamada al backend
                          final json = await _authApi.loginWithPhone(
                            phone: phone,
                            password: pass,
                          );

                          // 2) Token
                          final token =
                              (json['access_token'] ?? json['token'] ?? '')
                                  .toString();
                          if (token.isEmpty) {
                            throw Exception('Token no recibido del servidor');
                          }

                          // 3) Usuario (id y rol)
                          int? userId;
                          int? roleId;
                          if (json['user'] is Map) {
                            final user = json['user'] as Map;
                            userId = (user['id'] as num?)?.toInt();
                            roleId = (user['role_id'] as num?)
                                ?.toInt(); // 👈 rol
                          } else {
                            userId = (json['user_id'] as num?)?.toInt();
                            roleId = (json['role_id'] as num?)?.toInt();
                          }

                          // 4) Guardar sesión
                          await SecureStorage.saveToken(
                            token,
                          ); // cifrado (si lo usas)
                          await _session.saveSession(
                            token: token,
                            userId: userId,
                            roleId: roleId, // 👈 guardar rol
                          );

                          // 5) Feedback
                          if (!ctx.mounted) return;
                          await AppDialogs.success(
                            context: ctx,
                            title: '¡Bienvenido!',
                            message: 'Inicio de sesión exitoso.',
                            okText: 'Continuar',
                          );

                          // 6) Navegación según rol
                          if (!ctx.mounted) return;
                          final target = (roleId == 1)
                              ? '/admin'
                              : '/dashboard';
                          navigator.pushReplacementNamed(target);
                        } on AuthException catch (e) {
                          if (!ctx.mounted) return;
                          await AppDialogs.error(
                            context: ctx,
                            title: 'Error de autenticación',
                            message: e.message,
                          );
                        } catch (_) {
                          if (!ctx.mounted) return;
                          await AppDialogs.error(
                            context: ctx,
                            title: 'Error',
                            message: 'Error inesperado al iniciar sesión',
                          );
                        } finally {
                          if (mounted) setState(() => _loading = false);
                        }
                      },
                    ),
                  ),
                ),

                const SizedBox(height: 30),

                GestureDetector(
                  onTap: () {
                    Navigator.pushNamed(context, '/registro');
                  },
                  child: Text(
                    '¿No estás registrado? Regístrate aquí',
                    style: GoogleFonts.montserrat(
                      color: Colors.deepPurple[700],
                      fontSize: 14,
                      decoration: TextDecoration.underline,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
