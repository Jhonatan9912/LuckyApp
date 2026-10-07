// lib/web/widgets/aurora_background.dart
//
// Fondo animado: auroras doradas/violetas que se desplazan lentamente,
// una retícula sutil y partículas doradas flotando.
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/web_palette.dart';

class AuroraBackground extends StatefulWidget {
  final Widget child;
  final bool showGrid;

  /// false = fondo fijo (se pinta una sola vez). Úsalo en pantallas de trabajo
  /// para no redibujar toda la ventana en cada cuadro.
  final bool animate;

  const AuroraBackground({
    super.key,
    required this.child,
    this.showGrid = true,
    this.animate = true,
  });

  @override
  State<AuroraBackground> createState() => _AuroraBackgroundState();
}

class _AuroraBackgroundState extends State<AuroraBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 28),
    value: 0.15,
  );

  @override
  void initState() {
    super.initState();
    if (widget.animate) _ctrl.repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        const ColoredBox(color: WebPalette.bg),
        RepaintBoundary(
          child: AnimatedBuilder(
            animation: _ctrl,
            builder: (context, _) => CustomPaint(
              painter: _AuroraPainter(_ctrl.value, widget.showGrid),
            ),
          ),
        ),
        widget.child,
      ],
    );
  }
}

class _AuroraPainter extends CustomPainter {
  final double t;
  final bool showGrid;
  _AuroraPainter(this.t, this.showGrid);

  static final List<_Particle> _particles = List.generate(38, (i) {
    final r = math.Random(i * 7919);
    return _Particle(
      x: r.nextDouble(),
      y: r.nextDouble(),
      size: 0.8 + r.nextDouble() * 2.2,
      speed: 0.2 + r.nextDouble() * 0.8,
      phase: r.nextDouble() * math.pi * 2,
    );
  });

  void _blob(Canvas c, Offset center, double radius, Color color) {
    final paint = Paint()
      ..shader = RadialGradient(
        colors: [color, color.withValues(alpha: 0)],
      ).createShader(Rect.fromCircle(center: center, radius: radius));
    c.drawCircle(center, radius, paint);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final a = t * math.pi * 2;
    final w = size.width, h = size.height;
    final m = math.max(w, h);

    _blob(
      canvas,
      Offset(w * (0.18 + 0.08 * math.sin(a)), h * (0.22 + 0.06 * math.cos(a))),
      m * 0.45,
      WebPalette.gold.withValues(alpha: 0.16),
    );
    _blob(
      canvas,
      Offset(
        w * (0.82 + 0.06 * math.cos(a * 1.3)),
        h * (0.18 + 0.08 * math.sin(a)),
      ),
      m * 0.38,
      WebPalette.violet.withValues(alpha: 0.16),
    );
    _blob(
      canvas,
      Offset(
        w * (0.62 + 0.1 * math.sin(a * 0.7)),
        h * (0.92 + 0.05 * math.cos(a)),
      ),
      m * 0.42,
      WebPalette.amber.withValues(alpha: 0.10),
    );

    if (showGrid) {
      final grid = Paint()
        ..color = Colors.white.withValues(alpha: 0.025)
        ..strokeWidth = 1;
      const step = 64.0;
      for (double x = 0; x < w; x += step) {
        canvas.drawLine(Offset(x, 0), Offset(x, h), grid);
      }
      for (double y = 0; y < h; y += step) {
        canvas.drawLine(Offset(0, y), Offset(w, y), grid);
      }
    }

    for (final p in _particles) {
      final y = (p.y - t * p.speed) % 1.0;
      final x = p.x + 0.01 * math.sin(a * 2 + p.phase);
      final twinkle = 0.35 + 0.65 * (0.5 + 0.5 * math.sin(a * 6 + p.phase));
      canvas.drawCircle(
        Offset(x * w, y * h),
        p.size,
        Paint()..color = WebPalette.goldLight.withValues(alpha: 0.5 * twinkle),
      );
    }

    // Viñeta para dar profundidad
    final vignette = Paint()
      ..shader = RadialGradient(
        radius: 1.1,
        colors: [Colors.transparent, Colors.black.withValues(alpha: 0.55)],
      ).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, vignette);
  }

  @override
  bool shouldRepaint(covariant _AuroraPainter old) => old.t != t;
}

class _Particle {
  final double x, y, size, speed, phase;
  const _Particle({
    required this.x,
    required this.y,
    required this.size,
    required this.speed,
    required this.phase,
  });
}
