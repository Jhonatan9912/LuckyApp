// lib/web/screens/web_login_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:base_app/presentation/screens/login/login_action.dart';

import '../theme/web_palette.dart';
import '../widgets/gold_button.dart';
import 'web_auth_layout.dart';

class WebLoginScreen extends StatefulWidget {
  const WebLoginScreen({super.key});

  @override
  State<WebLoginScreen> createState() => _WebLoginScreenState();
}

class _WebLoginScreenState extends State<WebLoginScreen> {
  final _phone = TextEditingController();
  final _password = TextEditingController();
  bool _obscure = true;
  bool _loading = false;

  @override
  void dispose() {
    _phone.dispose();
    _password.dispose();
    super.dispose();
  }

  void _submit() {
    if (_loading) return;
    performLogin(
      context,
      phone: _phone.text.trim(),
      password: _password.text,
      setLoading: (v) => setState(() => _loading = v),
      isMounted: () => mounted,
    );
  }

  @override
  Widget build(BuildContext context) {
    return WebAuthLayout(
      form: AutofillGroup(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            const WebFormHeader(
              title: 'Bienvenido de nuevo',
              subtitle: 'Ingresa con tu número de celular para continuar.',
            ),
            const SizedBox(height: 32),
            TextField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              autofillHints: const [AutofillHints.telephoneNumberNational],
              textInputAction: TextInputAction.next,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(13),
              ],
              style: WebPalette.body(15.5, color: WebPalette.text),
              decoration: const InputDecoration(
                labelText: 'Número de celular',
                hintText: 'Ej: 3001234567',
                prefixIcon: Icon(Icons.phone_iphone_rounded, size: 20),
              ),
            ),
            const SizedBox(height: 18),
            TextField(
              controller: _password,
              obscureText: _obscure,
              autofillHints: const [AutofillHints.password],
              onSubmitted: (_) => _submit(),
              style: WebPalette.body(15.5, color: WebPalette.text),
              decoration: InputDecoration(
                labelText: 'Contraseña',
                prefixIcon: const Icon(Icons.lock_outline_rounded, size: 20),
                suffixIcon: IconButton(
                  tooltip: _obscure ? 'Mostrar' : 'Ocultar',
                  icon: Icon(
                    _obscure
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                    size: 20,
                  ),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Align(
              alignment: Alignment.centerRight,
              child: HoverLink(
                text: '¿Olvidaste tu contraseña?',
                size: 13.5,
                onTap: () => Navigator.pushNamed(context, '/restablecer'),
              ),
            ),
            const SizedBox(height: 26),
            GoldButton(
              label: 'Ingresar',
              icon: Icons.arrow_forward_rounded,
              loading: _loading,
              onPressed: _submit,
            ),
            const SizedBox(height: 28),
            Row(
              children: [
                Expanded(child: Divider(color: WebPalette.glassBorder)),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: Text(
                    '¿Nuevo en CM APP?',
                    style: WebPalette.body(13, color: WebPalette.textFaint),
                  ),
                ),
                Expanded(child: Divider(color: WebPalette.glassBorder)),
              ],
            ),
            const SizedBox(height: 20),
            Center(
              child: GhostButton(
                label: 'Crear una cuenta gratis',
                icon: Icons.person_add_alt_1_rounded,
                onPressed: () => Navigator.pushNamed(context, '/registro'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
