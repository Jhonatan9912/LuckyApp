// lib/presentation/screens/login/login_screen.dart
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
import 'dart:async';
// import 'package:base_app/core/config/env.dart'; // ❌ ya no se usa aquí
import 'package:provider/provider.dart';
import 'package:base_app/presentation/providers/subscription_provider.dart';

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

  // ❌ Eliminado: no crear AuthApi ni SessionManager locales
  // final _authApi = AuthApi(baseUrl: Env.apiBaseUrl);
  // final _session = SessionManager();

  @override
  void dispose() {
    phoneController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // ✅ Usar instancias globales desde Provider (con ApiClient y auto-refresh)
    final authApi = context.read<AuthApi>();
    final session = context.read<SessionManager>();

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
                        final subs = ctx.read<SubscriptionProvider>();
                        final navigator = Navigator.of(ctx, rootNavigator: true);

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
                          debugPrint('[LOGIN] 1. llamando API loginWithPhone...');
                          final json = await authApi
                              .loginWithPhone(phone: phone, password: pass)
                              .timeout(const Duration(seconds: 12));

                          // Access token
                          var token = (json['access_token'] ??
                                       json['token'] ??
                                       json['jwt'] ??
                                       '')
                              .toString()
                              .trim();
                          if (token.toLowerCase().startsWith('bearer ')) {
                            token = token.substring(7).trim();
                          }
                          if (token.isEmpty) {
                            throw AuthException('Token no recibido del servidor');
                          }

                          // Refresh token (opcional)
                          final refresh = (json['refresh_token'] ??
                                           json['refreshToken'])
                              ?.toString()
                              .trim();

                          // Usuario
                          int? userId, roleId;
                          if (json['user'] is Map) {
                            final user =
                                (json['user'] as Map).cast<String, dynamic>();
                            userId = (user['id'] as num?)?.toInt();
                            roleId = (user['role_id'] as num?)?.toInt();
                          } else {
                            userId = (json['user_id'] as num?)?.toInt();
                            roleId = (json['role_id'] as num?)?.toInt();
                          }
                          if (userId == null) {
                            throw AuthException('No se pudo obtener el ID de usuario');
                          }

                          // Guardar sesión (misma “fuente de verdad” que usa ApiClient)
                          await SecureStorage.saveToken(token).catchError((e) {
                            debugPrint('[LOGIN] SecureStorage error: $e');
                          });
                          await session.saveSession(
                            token: token,
                            refreshToken:
                                (refresh != null && refresh.isNotEmpty) ? refresh : null,
                            userId: userId,
                            roleId: roleId,
                          );

                          // Verifica persistencia
                          final saved = await session.getToken();
                          if (saved == null || saved.isEmpty) {
                            throw AuthException('No se pudo persistir la sesión local');
                          }

                          // 🔁 Refresca estado de suscripciones (no afecta sesión)
                          try {
                            await subs.refresh(force: true);
                          } catch (e) {
                            debugPrint('[LOGIN] subs.refresh error: $e');
                          }

                          // Mensaje amigable (no bloquea navegación)
                          unawaited(() async {
                            if (!ctx.mounted) return;
                            try {
                              await AppDialogs.success(
                                context: ctx,
                                title: '¡Bienvenido!',
                                message: 'Inicio de sesión exitoso.',
                                okText: 'Continuar',
                              );
                            } catch (_) {}
                          }());

                          // Navegación inmediata
                          // ⚠️ Si tu admin es roleId == 2, cámbialo aquí:
                          final target = (roleId == 1) ? '/admin' : '/dashboard';
                          navigator.pushNamedAndRemoveUntil(target, (_) => false);
                        } on AuthException catch (e) {
                          if (!ctx.mounted) return;
                          await AppDialogs.error(
                            context: ctx,
                            title: 'Error de autenticación',
                            message: e.message,
                          );
                        } on TimeoutException {
                          if (!ctx.mounted) return;
                          await AppDialogs.error(
                            context: ctx,
                            title: 'Tiempo agotado',
                            message:
                                'El servidor tardó demasiado. Intenta de nuevo.',
                          );
                        } catch (e) {
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
