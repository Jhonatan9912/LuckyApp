import 'package:flutter/material.dart';
import 'package:base_app/core/ui/dialogs.dart';
import 'package:provider/provider.dart';
import 'package:base_app/presentation/providers/notifications_provider.dart';

class AppTopbarActions extends StatelessWidget {
  final Future<void> Function() onLogout;
  const AppTopbarActions({super.key, required this.onLogout});

  Future<void> _confirmLogout(BuildContext context) async {
    final ok = await AppDialogs.confirmPlain(
      context: context,
      title: 'Cerrar sesión',
      message: '¿Seguro que deseas cerrar tu sesión?',
      okText: 'Cerrar sesión',
      destructive: true,
      icon: Icons.logout_rounded,
    );

    if (ok != true) return;

    // ✅ Después del await, antes de usar context:
    if (!context.mounted) return;

    // Captura lo necesario AHORA que comprobamos mounted
    final notifs = context.read<NotificationsProvider>();
    final navigator = Navigator.of(context, rootNavigator: true);

    // 🔔 Eliminar token remoto
    await notifs.onUserLoggedOut();

    // 🗑️ Ejecutar limpieza de sesión (tu callback)
    await onLogout();

    // 🚪 Navega usando el navigator capturado
    if (navigator.mounted) {
      navigator.pushNamedAndRemoveUntil('/login', (_) => false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: 'Cerrar sesión',
      icon: const Icon(Icons.logout),
      onPressed: () => _confirmLogout(context),
    );
  }
}
