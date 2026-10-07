// lib/web/widgets/glass_card.dart
import 'package:flutter/material.dart';

import '../theme/web_palette.dart';

/// Tarjeta con efecto vidrio esmerilado y borde luminoso.
class GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final bool glow;

  const GlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(28),
    this.radius = 24,
    this.glow = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.45),
            blurRadius: 40,
            offset: const Offset(0, 20),
          ),
          if (glow)
            BoxShadow(
              color: WebPalette.gold.withValues(alpha: 0.12),
              blurRadius: 60,
              spreadRadius: -10,
            ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        // Sin BackdropFilter: el fondo animado obligaría a re-desenfocar en cada
        // cuadro. Un relleno casi opaco da el mismo efecto con menos costo.
        child: DecoratedBox(
          decoration: const BoxDecoration(color: Color(0xCC0E0E15)),
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(radius),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Colors.white.withValues(alpha: 0.075),
                  Colors.white.withValues(alpha: 0.025),
                ],
              ),
              border: Border.all(color: WebPalette.glassBorder),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}
