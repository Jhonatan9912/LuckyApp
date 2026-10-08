// lib/presentation/screens/legal/account_privacy_screen.dart
//
// Pantalla "Mi cuenta y privacidad": accesos a los documentos legales y
// eliminación de la cuenta y los datos personales (Habeas Data, Ley 1581/2012).
import 'package:flutter/material.dart';

import 'package:base_app/data/api/account_api.dart';
import 'package:base_app/data/session/session_manager.dart';
import 'package:base_app/presentation/screens/legal/data_policy_screen.dart';
import 'package:base_app/presentation/screens/legal/terms_screen.dart';

class AccountPrivacyScreen extends StatefulWidget {
  const AccountPrivacyScreen({super.key});

  @override
  State<AccountPrivacyScreen> createState() => _AccountPrivacyScreenState();
}

class _AccountPrivacyScreenState extends State<AccountPrivacyScreen> {
  final _api = AccountApi();
  bool _busy = false;

  Future<void> _confirmDelete() async {
    final passCtrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Eliminar mi cuenta'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Esta acción elimina tu acceso y borra tus datos personales '
                '(nombre, documento, teléfono, correo y fecha de nacimiento) '
                'de forma permanente.\n\n'
                'Por obligación legal se conservan, ya anonimizados, los '
                'registros de pagos y comisiones.\n\n'
                'Para confirmar, escribe tu contraseña:',
              ),
              const SizedBox(height: 12),
              TextField(
                controller: passCtrl,
                obscureText: true,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Contraseña',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Eliminar'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;
    final password = passCtrl.text;
    if (password.isEmpty) {
      _snack('Debes escribir tu contraseña para confirmar.');
      return;
    }

    setState(() => _busy = true);
    try {
      final res = await _api.deleteMyAccount(password: password);
      if (!mounted) return;
      if (res.ok) {
        await SessionManager().clear();
        if (!mounted) return;
        Navigator.of(context, rootNavigator: true)
            .pushNamedAndRemoveUntil('/login', (_) => false);
        _snack('Tu cuenta y tus datos fueron eliminados.');
      } else {
        _snack(res.message);
      }
    } catch (e) {
      if (mounted) _snack('No se pudo eliminar la cuenta. Intenta de nuevo.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Mi cuenta y privacidad')),
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.description_outlined),
            title: const Text('Términos y Condiciones'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const TermsScreen()),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.privacy_tip_outlined),
            title: const Text('Tratamiento de Datos Personales'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const DataPolicyScreen()),
            ),
          ),
          const Divider(height: 32),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'Zona de riesgo',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: Colors.red,
                    fontWeight: FontWeight.bold,
                  ),
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'Puedes eliminar tu cuenta y tus datos personales en cualquier '
              'momento. Si tienes comisiones pendientes o una suscripción de '
              'pago activa, primero debes resolverlas.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.red,
                side: const BorderSide(color: Colors.red),
                minimumSize: const Size.fromHeight(48),
              ),
              icon: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.delete_forever),
              label: const Text('Eliminar mi cuenta'),
              onPressed: _busy ? null : _confirmDelete,
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
