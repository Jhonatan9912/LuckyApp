// lib/web/widgets/gold_button.dart
import 'package:flutter/material.dart';

import '../theme/web_palette.dart';

const _ink = Color(0xFF1A1300);

/// Botón principal dorado con brillo al pasar el mouse y destello animado.
class GoldButton extends StatefulWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool loading;
  final IconData? icon;
  final bool expand;

  const GoldButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.loading = false,
    this.icon,
    this.expand = true,
  });

  @override
  State<GoldButton> createState() => _GoldButtonState();
}

class _GoldButtonState extends State<GoldButton>
    with SingleTickerProviderStateMixin {
  bool _hover = false;
  late final AnimationController _shine = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2600),
  )..repeat();

  @override
  void dispose() {
    _shine.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null && !widget.loading;
    final lit = _hover && enabled;

    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: enabled ? widget.onPressed : null,
        child: AnimatedScale(
          scale: lit ? 1.02 : 1,
          duration: const Duration(milliseconds: 180),
          child: AnimatedOpacity(
            opacity: enabled || widget.loading ? 1 : 0.45,
            duration: const Duration(milliseconds: 200),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              height: 54,
              width: widget.expand ? double.infinity : null,
              decoration: BoxDecoration(
                gradient: WebPalette.goldGradient,
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: WebPalette.gold.withValues(alpha: lit ? 0.55 : 0.28),
                    blurRadius: lit ? 32 : 18,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    if (enabled)
                      Positioned.fill(
                        child: AnimatedBuilder(
                          animation: _shine,
                          builder: (context, _) => FractionalTranslation(
                            translation: Offset(-1.5 + _shine.value * 3, 0),
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    Colors.white.withValues(alpha: 0),
                                    Colors.white.withValues(alpha: 0.35),
                                    Colors.white.withValues(alpha: 0),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 28),
                      child: widget.loading
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.4,
                                color: _ink,
                              ),
                            )
                          : Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  widget.label,
                                  style: WebPalette.body(
                                    15.5,
                                    weight: FontWeight.w800,
                                    color: _ink,
                                  ),
                                ),
                                if (widget.icon != null) ...[
                                  const SizedBox(width: 10),
                                  AnimatedSlide(
                                    offset: Offset(_hover ? 0.25 : 0, 0),
                                    duration: const Duration(milliseconds: 180),
                                    child: Icon(
                                      widget.icon,
                                      size: 19,
                                      color: _ink,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Botón secundario con borde de vidrio.
class GhostButton extends StatefulWidget {
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;

  const GhostButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
  });

  @override
  State<GhostButton> createState() => _GhostButtonState();
}

class _GhostButtonState extends State<GhostButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onPressed,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          height: 50,
          padding: const EdgeInsets.symmetric(horizontal: 22),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            color: Colors.white.withValues(alpha: _hover ? 0.08 : 0.03),
            border: Border.all(
              color: _hover
                  ? WebPalette.gold.withValues(alpha: 0.6)
                  : WebPalette.glassBorder,
            ),
          ),
          // Centrado si recibe un ancho fijo; ajustado al contenido si no.
          child: Center(
            widthFactor: 1,
            heightFactor: 1,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.icon != null) ...[
                  Icon(widget.icon, size: 18, color: WebPalette.goldLight),
                  const SizedBox(width: 10),
                ],
                Text(
                  widget.label,
                  style: WebPalette.body(
                    14.5,
                    weight: FontWeight.w700,
                    color: WebPalette.text,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Enlace de texto dorado con subrayado animado al pasar el mouse.
class HoverLink extends StatefulWidget {
  final String text;
  final VoidCallback onTap;
  final double size;

  const HoverLink({
    super.key,
    required this.text,
    required this.onTap,
    this.size = 14,
  });

  @override
  State<HoverLink> createState() => _HoverLinkState();
}

class _HoverLinkState extends State<HoverLink> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.text,
              style: WebPalette.body(
                widget.size,
                weight: FontWeight.w700,
                color: _hover ? WebPalette.goldLight : WebPalette.gold,
              ),
            ),
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              height: 1.5,
              width: _hover ? widget.text.length * widget.size * 0.52 : 0,
              color: WebPalette.goldLight,
            ),
          ],
        ),
      ),
    );
  }
}
