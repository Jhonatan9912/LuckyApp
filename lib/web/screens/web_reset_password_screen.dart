// lib/web/screens/web_reset_password_screen.dart
//
// Recuperar contraseña en 3 pasos: correo → código → nueva contraseña.
// Usa los mismos endpoints que la app.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:base_app/core/config/env.dart';
import 'package:base_app/core/validation/validators.dart';
import 'package:base_app/data/api/auth_api.dart';

import '../alerts/web_alerts.dart';
import '../theme/web_palette.dart';
import '../widgets/gold_button.dart';
import 'web_auth_layout.dart';

class WebResetPasswordScreen extends StatefulWidget {
  const WebResetPasswordScreen({super.key});

  @override
  State<WebResetPasswordScreen> createState() => _WebResetPasswordScreenState();
}

class _WebResetPasswordScreenState extends State<WebResetPasswordScreen> {
  final _api = AuthApi(baseUrl: Env.apiBaseUrl);
  final _email = TextEditingController();
  final _code = TextEditingController();
  final _pass = TextEditingController();
  final _confirm = TextEditingController();
  int _step = 0;
  bool _loading = false;
  bool _obscure = true;
  String? _token;

  @override
  void dispose() {
    for (final c in [_email, _code, _pass, _confirm]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _run(Future<void> Function() task) async {
    setState(() => _loading = true);
    try {
      await task();
    } on AuthException catch (e) {
      await WebAlerts.dialog(
        title: 'No se pudo continuar',
        message: e.message,
        tone: AlertTone.error,
      );
    } catch (_) {
      await WebAlerts.dialog(
        title: 'Error',
        message: 'Ocurrió un error inesperado. Intenta de nuevo.',
        tone: AlertTone.error,
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _sendCode() {
    final err = Validators.email(_email.text);
    if (err != null) return WebAlerts.toast(err, tone: AlertTone.warning);
    _run(() async {
      await _api.requestPasswordResetByEmail(email: _email.text.trim());
      WebAlerts.toast(
        'Si el correo está registrado, te llegará un código en unos segundos.',
        title: 'Código enviado',
        tone: AlertTone.success,
      );
      setState(() => _step = 1);
    });
  }

  void _verify() {
    final err = Validators.otp(_code.text);
    if (err != null) return WebAlerts.toast(err, tone: AlertTone.warning);
    _run(() async {
      _token = await _api.verifyResetCodeByEmail(
        email: _email.text.trim(),
        code: _code.text.trim(),
      );
      WebAlerts.toast(
        'Ahora crea tu nueva contraseña.',
        title: 'Código verificado',
        tone: AlertTone.success,
      );
      setState(() => _step = 2);
    });
  }

  void _save() {
    final err = Validators.password(_pass.text);
    if (err != null) return WebAlerts.toast(err, tone: AlertTone.warning);
    if (_pass.text.trim() != _confirm.text.trim()) {
      return WebAlerts.toast(
        'Las contraseñas no coinciden.',
        tone: AlertTone.warning,
      );
    }
    final nav = Navigator.of(context);
    _run(() async {
      await _api.confirmPasswordReset(
        resetToken: _token!,
        newPassword: _pass.text.trim(),
      );
      WebAlerts.toast(
        'Ya puedes iniciar sesión con tu nueva contraseña.',
        title: 'Contraseña actualizada',
        tone: AlertTone.success,
      );
      nav.pushNamedAndRemoveUntil('/login', (_) => false);
    });
  }

  Widget _field(
    TextEditingController c,
    String label,
    IconData icon, {
    bool obscure = false,
    Widget? suffix,
    List<TextInputFormatter>? fmt,
    VoidCallback? onSubmit,
  }) {
    return TextField(
      controller: c,
      obscureText: obscure,
      inputFormatters: fmt,
      onSubmitted: onSubmit == null ? null : (_) => onSubmit(),
      style: WebPalette.body(15.5, color: WebPalette.text),
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, size: 20),
        suffixIcon: suffix,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const titles = [
      'Recupera tu cuenta',
      'Revisa tu correo',
      'Nueva contraseña',
    ];
    final subtitles = [
      'Te enviaremos un código de verificación a tu correo.',
      'Escribe el código que enviamos a ${_email.text.trim()}.',
      'Elige una contraseña de al menos 6 caracteres.',
    ];

    final step = switch (_step) {
      0 => Column(
        key: const ValueKey(0),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _field(
            _email,
            'Correo electrónico',
            Icons.alternate_email_rounded,
            onSubmit: _sendCode,
          ),
          const SizedBox(height: 24),
          GoldButton(
            label: 'Enviar código',
            icon: Icons.send_rounded,
            loading: _loading,
            onPressed: _sendCode,
          ),
        ],
      ),
      1 => Column(
        key: const ValueKey(1),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _field(
            _code,
            'Código de verificación',
            Icons.pin_outlined,
            fmt: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(6),
            ],
            onSubmit: _verify,
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: HoverLink(
              text: 'Reenviar código',
              size: 13.5,
              onTap: _loading ? () {} : _sendCode,
            ),
          ),
          const SizedBox(height: 20),
          GoldButton(
            label: 'Verificar código',
            icon: Icons.verified_rounded,
            loading: _loading,
            onPressed: _verify,
          ),
        ],
      ),
      _ => Column(
        key: const ValueKey(2),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _field(
            _pass,
            'Nueva contraseña',
            Icons.lock_outline_rounded,
            obscure: _obscure,
            suffix: IconButton(
              icon: Icon(
                _obscure
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
                size: 20,
              ),
              onPressed: () => setState(() => _obscure = !_obscure),
            ),
          ),
          const SizedBox(height: 16),
          _field(
            _confirm,
            'Confirmar contraseña',
            Icons.lock_reset_rounded,
            obscure: _obscure,
            onSubmit: _save,
          ),
          const SizedBox(height: 24),
          GoldButton(
            label: 'Guardar contraseña',
            icon: Icons.check_rounded,
            loading: _loading,
            onPressed: _save,
          ),
        ],
      ),
    };

    return WebAuthLayout(
      form: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              IconButton(
                tooltip: 'Volver',
                onPressed: () => _step == 0
                    ? Navigator.maybePop(context)
                    : setState(() => _step--),
                icon: const Icon(
                  Icons.arrow_back_rounded,
                  color: WebPalette.textMuted,
                ),
              ),
              const Spacer(),
              for (var i = 0; i < 3; i++)
                AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  margin: const EdgeInsets.only(left: 6),
                  width: i == _step ? 26 : 8,
                  height: 8,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    color: i <= _step
                        ? WebPalette.gold
                        : Colors.white.withValues(alpha: 0.12),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          WebFormHeader(title: titles[_step], subtitle: subtitles[_step]),
          const SizedBox(height: 28),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 280),
            child: step,
          ),
          const SizedBox(height: 22),
          Center(
            child: HoverLink(
              text: 'Volver a iniciar sesión',
              onTap: () => Navigator.pushNamedAndRemoveUntil(
                context,
                '/login',
                (_) => false,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
