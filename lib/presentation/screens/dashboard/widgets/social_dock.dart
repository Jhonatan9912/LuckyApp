// lib/presentation/screens/dashboard/widgets/social_dock.dart
import 'package:flutter/material.dart';
import 'package:base_app/core/ui/brand_icons.dart';
import 'package:base_app/core/config/links.dart';
import 'package:base_app/core/utils/url_utils.dart';

class SocialDock extends StatelessWidget {
  final double bottomPadding;
  const SocialDock({super.key, this.bottomPadding = 24});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bg = theme.colorScheme.surface.withValues(alpha: 0.92);

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
                // área táctil cómoda
                padding: EdgeInsets.all(12),
                // El icono va DENTRO del InkWell (no encima)
                child: IconTheme(
                  data: IconThemeData(size: 18),
                  child: SizedBox(), // placeholder, lo ponemos abajo
                ),
              ),
            ),
          ),
        ),
      );
    }

    // Versión sin Stack: metemos el Icon directamente
    Widget circleWithIcon({
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
                padding: EdgeInsets.all(12),
                child: SizedBox(width: 24, height: 24, child: Center()),
              ),
            ),
          ),
        ),
      );
    }

    // Más simple aún: directamente este helper
    Widget item({
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
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Icon(icon, size: 18), // 👈 icono dentro del InkWell
              ),
            ),
          ),
        ),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        item(
          icon: BrandIcons.whatsapp,
          tooltip: 'Comunidad en WhatsApp',
          onTap: () => UrlUtils.openExternal(
            context,
            url: AppLinks.whatsappChannel,
          ),
        ),
        const SizedBox(height: 10),
        item(
          icon: BrandIcons.facebookF,
          tooltip: 'Página en Facebook',
          onTap: () => UrlUtils.openExternal(
            context,
            url: AppLinks.facebookShare,
          ),
        ),
      ],
    );
  }
}
