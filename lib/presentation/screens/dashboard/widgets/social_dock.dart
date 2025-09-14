// lib/presentation/screens/dashboard/widgets/social_dock.dart
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:base_app/core/config/links.dart';
import 'package:base_app/core/utils/url_utils.dart';

class SocialDock extends StatelessWidget {
  final double bottomPadding;
  const SocialDock({super.key, this.bottomPadding = 24});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // ✅ Reemplazo deprecado: withValues(alpha: 0.92)
    final bg = theme.colorScheme.surface.withValues(alpha: 0.92);

    // ✅ Renombrada (sin guion bajo)
    Widget circle({
      required IconData icon,
      required String tooltip,
      required VoidCallback onTap,
    }) {
      return Tooltip(
        message: tooltip,
        child: Semantics(
          button: true,
          label: tooltip,
          child: Material(
            color: bg,
            shape: const CircleBorder(),
            elevation: 2,
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onTap,
              child: const Padding(
                padding: EdgeInsets.all(10),
                child: SizedBox(width: 24, height: 24), // asegura área táctil
              ),
            ),
          ),
        ),
      );
    }

    return IgnorePointer(
      ignoring: false,
      child: Opacity(
        opacity: 0.98,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ícono WhatsApp
            Stack(
              alignment: Alignment.center,
              children: [
                circle(
                  icon: FontAwesomeIcons.whatsapp,
                  tooltip: 'Comunidad en WhatsApp',
                  onTap: () => UrlUtils.openExternal(
                    context,
                    url: AppLinks.whatsappChannel,
                  ),
                ),
                const Positioned(
                  child: FaIcon(FontAwesomeIcons.whatsapp, size: 18),
                ),
              ],
            ),
            const SizedBox(height: 10),
            // ícono Facebook
            Stack(
              alignment: Alignment.center,
              children: [
                circle(
                  icon: FontAwesomeIcons.facebookF,
                  tooltip: 'Página en Facebook',
                  onTap: () => UrlUtils.openExternal(
                    context,
                    url: AppLinks.facebookShare,
                  ),
                ),
                const Positioned(
                  child: FaIcon(FontAwesomeIcons.facebookF, size: 18),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
