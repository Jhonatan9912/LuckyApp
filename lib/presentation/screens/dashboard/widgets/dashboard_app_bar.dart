import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:base_app/presentation/widgets/app_topbar_actions.dart';
import '../controller/dashboard_controller.dart'; // 👈 importa el controller
import 'notification_icon.dart';

class DashboardAppBar extends StatelessWidget implements PreferredSizeWidget {
  final VoidCallback onHelp;
  final bool isLoggedIn;
  final Future<void> Function() onLogout;
  final DashboardController ctrl; // 👈 nuevo
  final VoidCallback onBellTap;    // 👈 NO nulo

  const DashboardAppBar({
    super.key,
    required this.onHelp,
    required this.isLoggedIn,
    required this.onLogout,
    required this.ctrl,
    required this.onBellTap, // 👈 requerido
  });

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      automaticallyImplyLeading: false,
      leading: IconButton(
        icon: const Icon(Icons.help_outline),
        tooltip: 'Ayuda',
        onPressed: onHelp,
      ),
      title: TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: 0.0, end: 1.0),
        duration: const Duration(milliseconds: 800),
        builder: (context, value, child) => Opacity(
          opacity: value,
          child: Transform.scale(
            scale: value,
            child: Text(
              'Sorteo en Vivo',
              style: GoogleFonts.montserrat(
                fontWeight: FontWeight.bold,
                color: Colors.orange[800],
              ),
            ),
          ),
        ),
      ),
      backgroundColor: Colors.white,
      elevation: 1,
      centerTitle: true,
      iconTheme: const IconThemeData(color: Colors.deepPurple),
      actions: [
        if (isLoggedIn) ...[
          NotificationIcon(
            unreadCount: ctrl.unreadCount,
            onPressed: onBellTap, // ✅ único onPressed, no nulo
          ),
          AppTopbarActions(
            onLogout: () async {
              await onLogout();
            },
          ),
        ],
      ],
    );
  }
}
