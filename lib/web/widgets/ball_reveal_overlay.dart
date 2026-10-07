// lib/web/widgets/ball_reveal_overlay.dart
//
// Revelado de balotas al reservar, sobre toda la pantalla:
// fondo oscurecido con foco dorado, rayos de luz girando, destellos en órbita
// y la balota entrando con giro y rebote; al cambiar de balota, la anterior
// sale volando hacia arriba.
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/web_palette.dart';
import 'lottery_ball.dart';

class BallRevealOverlay extends StatefulWidget {
  /// true mientras dura toda la secuencia de reserva.
  final bool active;

  /// Número ya formateado de la balota actual (null entre balotas).
  final String? number;

  /// Balota actual (1..total).
  final int index;
  final int total;

  const BallRevealOverlay({
    super.key,
    required this.active,
    required this.number,
    required this.index,
    this.total = 5,
  });

  @override
  State<BallRevealOverlay> createState() => _BallRevealOverlayState();
}

class _BallRevealOverlayState extends State<BallRevealOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _spin = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 12),
  );

  @override
  void initState() {
    super.initState();
    if (widget.active) _spin.repeat();
  }

  @override
  void didUpdateWidget(covariant BallRevealOverlay old) {
    super.didUpdateWidget(old);
    if (widget.active && !_spin.isAnimating) _spin.repeat();
    if (!widget.active && _spin.isAnimating) _spin.stop();
  }

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final ball = (math.min(size.width, size.height) * 0.32).clamp(140.0, 240.0);

    return IgnorePointer(
      ignoring: !widget.active,
      child: AnimatedOpacity(
        opacity: widget.active ? 1 : 0,
        duration: const Duration(milliseconds: 350),
        child: SizedBox.expand(
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Fondo con foco dorado
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      radius: 0.9,
                      colors: [
                        WebPalette.gold.withValues(alpha: 0.22),
                        Colors.black.withValues(alpha: 0.78),
                      ],
                    ),
                  ),
                ),
              ),
              // Rayos y destellos girando
              RepaintBoundary(
                child: AnimatedBuilder(
                  animation: _spin,
                  builder: (context, _) => CustomPaint(
                    size: Size.square(ball * 3.2),
                    painter: _RaysPainter(_spin.value),
                  ),
                ),
              ),
              // Balota
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 650),
                reverseDuration: const Duration(milliseconds: 280),
                transitionBuilder: (child, anim) {
                  final entering =
                      anim.status == AnimationStatus.forward ||
                      anim.status == AnimationStatus.completed;
                  if (!entering) {
                    // Sale volando hacia arriba y se encoge
                    return FadeTransition(
                      opacity: anim,
                      child: SlideTransition(
                        position:
                            Tween(
                              begin: const Offset(0, -1.4),
                              end: Offset.zero,
                            ).animate(
                              CurvedAnimation(
                                parent: anim,
                                curve: Curves.easeIn,
                              ),
                            ),
                        child: ScaleTransition(scale: anim, child: child),
                      ),
                    );
                  }
                  final pop = CurvedAnimation(
                    parent: anim,
                    curve: Curves.elasticOut,
                  );
                  return FadeTransition(
                    opacity: CurvedAnimation(
                      parent: anim,
                      curve: const Interval(0, 0.3),
                    ),
                    child: SlideTransition(
                      position:
                          Tween(
                            begin: const Offset(0, 0.9),
                            end: Offset.zero,
                          ).animate(
                            CurvedAnimation(
                              parent: anim,
                              curve: Curves.easeOutCubic,
                            ),
                          ),
                      child: RotationTransition(
                        turns: Tween(begin: -0.35, end: 0.0).animate(
                          CurvedAnimation(
                            parent: anim,
                            curve: Curves.easeOutBack,
                          ),
                        ),
                        child: ScaleTransition(
                          scale: Tween(begin: 0.25, end: 1.0).animate(pop),
                          child: child,
                        ),
                      ),
                    ),
                  );
                },
                child: widget.number == null
                    ? SizedBox(
                        key: const ValueKey('empty'),
                        width: ball,
                        height: ball,
                      )
                    : LotteryBall(
                        key: ValueKey('ball-${widget.index}-${widget.number}'),
                        number: widget.number!,
                        size: ball,
                      ),
              ),
              // Texto y progreso
              Positioned(
                bottom: size.height * 0.12,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Reservando tu jugada',
                      style: WebPalette.display(20, weight: FontWeight.w800),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Balota ${widget.index.clamp(1, widget.total)} de ${widget.total}',
                      style: WebPalette.body(
                        14,
                        color: WebPalette.goldLight,
                        weight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (var i = 1; i <= widget.total; i++)
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 300),
                            margin: const EdgeInsets.symmetric(horizontal: 4),
                            width: i == widget.index ? 28 : 10,
                            height: 10,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(10),
                              gradient: i <= widget.index
                                  ? WebPalette.goldGradient
                                  : null,
                              color: i <= widget.index
                                  ? null
                                  : Colors.white.withValues(alpha: 0.15),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RaysPainter extends CustomPainter {
  final double t;
  _RaysPainter(this.t);

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2;
    final a = t * math.pi * 2;

    // Rayos de luz
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.rotate(a);
    const rays = 14;
    for (var i = 0; i < rays; i++) {
      final ang = i * 2 * math.pi / rays;
      final path = Path()
        ..moveTo(0, 0)
        ..lineTo(math.cos(ang - 0.07) * r, math.sin(ang - 0.07) * r)
        ..lineTo(math.cos(ang + 0.07) * r, math.sin(ang + 0.07) * r)
        ..close();
      canvas.drawPath(
        path,
        Paint()
          ..shader = RadialGradient(
            colors: [
              WebPalette.goldLight.withValues(alpha: 0.28),
              WebPalette.gold.withValues(alpha: 0),
            ],
          ).createShader(Rect.fromCircle(center: Offset.zero, radius: r)),
      );
    }
    canvas.restore();

    // Destellos en órbita (giran al revés)
    for (var i = 0; i < 10; i++) {
      final ang = -a * 1.6 + i * 2 * math.pi / 10;
      final orbit = r * (0.42 + 0.08 * math.sin(a * 4 + i));
      final p = c + Offset(math.cos(ang) * orbit, math.sin(ang) * orbit);
      final tw = 0.5 + 0.5 * math.sin(a * 10 + i * 1.7);
      canvas.drawCircle(
        p,
        2.0 + 2.5 * tw,
        Paint()..color = WebPalette.goldLight.withValues(alpha: 0.4 + 0.6 * tw),
      );
      canvas.drawCircle(
        p,
        8 + 6 * tw,
        Paint()..color = WebPalette.gold.withValues(alpha: 0.10 * tw),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _RaysPainter old) => old.t != t;
}
