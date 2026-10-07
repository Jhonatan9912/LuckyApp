// lib/web/screens/web_register_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:base_app/data/api/api_service.dart';
import 'package:base_app/presentation/screens/register/register_logic.dart';

import '../theme/web_palette.dart';
import '../widgets/gold_button.dart';
import 'web_auth_layout.dart';

class WebRegisterScreen extends StatefulWidget {
  const WebRegisterScreen({super.key});

  @override
  State<WebRegisterScreen> createState() => _WebRegisterScreenState();
}

class _WebRegisterScreenState extends State<WebRegisterScreen> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _idNumber = TextEditingController();
  final _countryCode = TextEditingController(text: '+57');
  final _phone = TextEditingController();
  final _birthDate = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  final _referral = TextEditingController();

  List<Map<String, dynamic>> _idTypes = [];
  bool _loadingTypes = true;
  String? _idType;
  bool _wasReferred = false;
  bool _acceptTerms = false;
  bool _acceptData = false;
  bool _obscure = true;
  bool _submitting = false;

  bool get _canSubmit => !_submitting && _acceptTerms && _acceptData;

  @override
  void initState() {
    super.initState();
    _loadIdTypes();
  }

  Future<void> _loadIdTypes() async {
    try {
      final data = await ApiService().fetchIdentificationTypes();
      if (mounted) setState(() => _idTypes = data);
    } catch (e) {
      debugPrint('Error al cargar tipos de identificación: $e');
    } finally {
      if (mounted) setState(() => _loadingTypes = false);
    }
  }

  @override
  void dispose() {
    for (final c in [
      _name,
      _email,
      _idNumber,
      _countryCode,
      _phone,
      _birthDate,
      _password,
      _confirm,
      _referral,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pickBirthDate() async {
    final now = DateTime.now();
    final lastAllowed = DateTime(now.year - 18, now.month, now.day);
    final picked = await showDatePicker(
      context: context,
      initialDate: lastAllowed,
      firstDate: DateTime(1900),
      lastDate: lastAllowed,
      helpText: 'Selecciona tu fecha de nacimiento',
      locale: const Locale('es', 'CO'),
      builder: (ctx, child) => Theme(data: Theme.of(context), child: child!),
    );
    if (picked != null) {
      _birthDate.text = '${picked.day}/${picked.month}/${picked.year}';
    }
  }

  void _toast(String msg, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: error
            ? const Color(0xFF3A1416)
            : const Color(0xFF0F2A1E),
        content: Row(
          children: [
            Icon(
              error
                  ? Icons.error_outline_rounded
                  : Icons.check_circle_outline_rounded,
              color: error ? WebPalette.danger : WebPalette.emerald,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                msg,
                style: WebPalette.body(14, color: WebPalette.text),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _submit() async {
    if (!_canSubmit) return;
    final data = RegisterFormData(
      name: _name.text,
      rawPhone: _phone.text,
      rawCountryCode: _countryCode.text,
      birthDate: _birthDate.text,
      password: _password.text,
      confirmPassword: _confirm.text,
      email: _email.text,
      idNumber: _idNumber.text,
      idType: _idType,
      wasReferred: _wasReferred,
      referralCode: _referral.text,
      acceptTerms: _acceptTerms,
      acceptData: _acceptData,
    );

    final invalid = data.validate();
    if (invalid != null) {
      _toast(invalid, error: true);
      return;
    }

    setState(() => _submitting = true);
    try {
      final error = await submitRegistration(context, data);
      if (error != null) {
        _toast(error, error: true);
        return;
      }
      _toast('¡Cuenta creada! Ya puedes iniciar sesión.');
      await Future.delayed(const Duration(milliseconds: 1500));
      if (!mounted) return;
      Navigator.pushReplacementNamed(context, '/login');
    } catch (e) {
      _toast('Error: $e', error: true);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  TextStyle get _fieldStyle => WebPalette.body(15, color: WebPalette.text);

  Widget _field(
    TextEditingController c,
    String label, {
    IconData? icon,
    String? hint,
    TextInputType? keyboard,
    List<TextInputFormatter>? formatters,
    bool obscure = false,
    Widget? suffix,
    bool readOnly = false,
    VoidCallback? onTap,
  }) {
    return TextField(
      controller: c,
      keyboardType: keyboard,
      inputFormatters: formatters,
      obscureText: obscure,
      readOnly: readOnly,
      onTap: onTap,
      style: _fieldStyle,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: icon == null ? null : Icon(icon, size: 20),
        suffixIcon: suffix,
      ),
    );
  }

  Widget _pair(bool wide, Widget a, Widget b) {
    if (!wide) {
      return Column(children: [a, const SizedBox(height: 16), b]);
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: a),
        const SizedBox(width: 16),
        Expanded(child: b),
      ],
    );
  }

  Widget _idTypeField() {
    if (_loadingTypes) {
      return const InputDecorator(
        decoration: InputDecoration(
          labelText: 'Tipo de documento',
          prefixIcon: Icon(Icons.badge_outlined, size: 20),
        ),
        child: LinearProgressIndicator(minHeight: 2),
      );
    }
    return DropdownButtonFormField<String>(
      value: _idType,
      isExpanded: true,
      dropdownColor: WebPalette.bgElevated,
      borderRadius: BorderRadius.circular(14),
      style: _fieldStyle,
      decoration: const InputDecoration(
        labelText: 'Tipo de documento',
        prefixIcon: Icon(Icons.badge_outlined, size: 20),
      ),
      items: [
        for (final t in _idTypes)
          DropdownMenuItem(
            value: t['id'].toString(),
            child: Text('${t['name']}'),
          ),
      ],
      onChanged: (v) => setState(() => _idType = v),
    );
  }

  Widget _check({
    required bool value,
    required ValueChanged<bool> onChanged,
    required String prefix,
    String? link,
    VoidCallback? onLink,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => onChanged(!value),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Checkbox(value: value, onChanged: (v) => onChanged(v ?? false)),
            const SizedBox(width: 4),
            Expanded(
              child: Wrap(
                spacing: 5,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    prefix,
                    style: WebPalette.body(14, color: WebPalette.textMuted),
                  ),
                  if (link != null)
                    HoverLink(text: link, size: 14, onTap: onLink ?? () {}),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return WebAuthLayout(
      formMaxWidth: 640,
      form: LayoutBuilder(
        builder: (context, c) {
          final wide = c.maxWidth >= 520;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  IconButton(
                    tooltip: 'Volver',
                    onPressed: () => Navigator.maybePop(context),
                    icon: const Icon(
                      Icons.arrow_back_rounded,
                      color: WebPalette.textMuted,
                    ),
                  ),
                  const SizedBox(width: 6),
                  const Expanded(
                    child: WebFormHeader(
                      title: 'Crea tu cuenta',
                      subtitle: 'Es gratis y toma menos de un minuto.',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 28),
              _pair(
                wide,
                _field(
                  _name,
                  'Nombre completo',
                  icon: Icons.person_outline_rounded,
                ),
                _field(
                  _email,
                  'Correo electrónico',
                  icon: Icons.alternate_email_rounded,
                  hint: 'ejemplo@correo.com',
                  keyboard: TextInputType.emailAddress,
                ),
              ),
              const SizedBox(height: 16),
              _pair(
                wide,
                _idTypeField(),
                _field(
                  _idNumber,
                  'Número de documento',
                  icon: Icons.numbers_rounded,
                  formatters: [LengthLimitingTextInputFormatter(15)],
                ),
              ),
              const SizedBox(height: 16),
              _pair(
                wide,
                Row(
                  children: [
                    SizedBox(
                      width: 92,
                      child: _field(
                        _countryCode,
                        'País',
                        formatters: [
                          FilteringTextInputFormatter.allow(RegExp(r'[0-9+]')),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _field(
                        _phone,
                        'Celular',
                        icon: Icons.phone_iphone_rounded,
                        keyboard: TextInputType.phone,
                        formatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(13),
                        ],
                      ),
                    ),
                  ],
                ),
                _field(
                  _birthDate,
                  'Fecha de nacimiento',
                  icon: Icons.cake_outlined,
                  readOnly: true,
                  onTap: _pickBirthDate,
                  suffix: const Icon(Icons.calendar_month_rounded, size: 20),
                ),
              ),
              const SizedBox(height: 16),
              _pair(
                wide,
                _field(
                  _password,
                  'Contraseña',
                  icon: Icons.lock_outline_rounded,
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
                _field(
                  _confirm,
                  'Confirmar contraseña',
                  icon: Icons.lock_reset_rounded,
                  obscure: _obscure,
                ),
              ),
              const SizedBox(height: 18),
              _check(
                value: _wasReferred,
                onChanged: (v) => setState(() => _wasReferred = v),
                prefix: '¿Alguien te invitó? Tengo un código de referido',
              ),
              AnimatedSize(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOutCubic,
                child: _wasReferred
                    ? Padding(
                        padding: const EdgeInsets.only(top: 8, bottom: 8),
                        child: _field(
                          _referral,
                          'Código de referido',
                          icon: Icons.card_giftcard_rounded,
                        ),
                      )
                    : const SizedBox(width: double.infinity),
              ),
              _check(
                value: _acceptTerms,
                onChanged: (v) => setState(() => _acceptTerms = v),
                prefix: 'Acepto los',
                link: 'Términos y Condiciones',
                onLink: () => Navigator.pushNamed(context, '/terminos'),
              ),
              _check(
                value: _acceptData,
                onChanged: (v) => setState(() => _acceptData = v),
                prefix: 'Acepto el',
                link: 'Tratamiento de Datos',
                onLink: () => Navigator.pushNamed(context, '/datos'),
              ),
              const SizedBox(height: 24),
              GoldButton(
                label: 'Crear mi cuenta',
                icon: Icons.arrow_forward_rounded,
                loading: _submitting,
                onPressed: _canSubmit ? _submit : null,
              ),
              const SizedBox(height: 22),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('¿Ya tienes cuenta?', style: WebPalette.body(14)),
                  const SizedBox(width: 8),
                  HoverLink(
                    text: 'Inicia sesión',
                    onTap: () =>
                        Navigator.pushReplacementNamed(context, '/login'),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}
