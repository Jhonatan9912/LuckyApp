import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:base_app/core/utils/url_utils.dart';
import 'package:base_app/core/config/links.dart';

/// Composición: etiqueta vertical + íconos sociales
class SocialDockWithLabel extends StatelessWidget {
  const SocialDockWithLabel({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final base = theme.colorScheme.surface.withValues(alpha: 0.95);
    final border = theme.colorScheme.outlineVariant.withValues(alpha: 0.35);
    final textColor = theme.colorScheme.onSurface.withValues(alpha: 0.85);

    // Etiqueta vertical “Síguenos” con flecha
    final label = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Texto vertical
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: base,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: border),
            boxShadow: const [
              BoxShadow(
                color: Colors.black12,
                blurRadius: 6,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: RotatedBox(
            quarterTurns: 3, // vertical
            child: Text(
              'Contactar asesor',
              style: TextStyle(
                color: textColor,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.3,
                fontSize: 12,
              ),
            ),

          ),
        ),
        const SizedBox(height: 6),
        // Flechita hacia abajo apuntando a los iconos
        Icon(
          Icons.keyboard_arrow_down,
          size: 18,
          color: textColor,
        ),
      ],
    );

    // Botón social reutilizable
    Widget item({
      required IconData icon,
      required String tooltip,
      required VoidCallback onTap,
      Color? color,
    }) {
      return Tooltip(
        message: tooltip,
        child: Semantics(
          button: true,
          label: tooltip,
          child: Material(
            color: base,
            shape: const CircleBorder(),
            elevation: 2,
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: FaIcon(icon, size: 18, color: color),
              ),
            ),
          ),
        ),
      );
    }

    // Columna con los iconos
    final icons = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
      item(
        icon: FontAwesomeIcons.whatsapp,
        color: const Color(0xFF25D366),
        tooltip: 'Contactar asesor por WhatsApp',
        onTap: () => UrlUtils.openExternal(
          context,
          url: AppLinks.whatsappAdvisor,
        ),
      ),

        const SizedBox(height: 10),
        item(
          icon: FontAwesomeIcons.facebookF,
          color: const Color(0xFF1877F2),
          tooltip: 'Página en Facebook',
          onTap: () => UrlUtils.openExternal(
            context,
            url: AppLinks.facebookShare,
          ),
        ),
      ],
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        label,
        const SizedBox(height: 10),
        icons,
      ],
    );
  }
}
