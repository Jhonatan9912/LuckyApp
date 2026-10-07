// lib/presentation/screens/login/login_screen.dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'widgets/phone_input.dart';
import 'widgets/password_input.dart';
import 'widgets/login_button.dart';
import 'widgets/forgot_password_button.dart';
import 'login_action.dart';
// import 'package:base_app/core/config/env.dart'; // ❌ ya no se usa aquí

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

Image.asset(
  'assets/icons/iconowithout.png',
  width: 180,      // ← ajusta el tamaño a tu gusto
  height: 180,
),
                const SizedBox(height: 10),
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
                      onPressed: () => performLogin(
                        context,
                        phone: phoneController.text.trim(),
                        password: passwordController.text,
                        setLoading: (v) => setState(() => _loading = v),
                        isMounted: () => mounted,
                      ),
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
