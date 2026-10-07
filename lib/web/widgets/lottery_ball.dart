// lib/web/widgets/lottery_ball.dart
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/web_palette.dart';

/// Esfera tipo balota con número, iluminación 3D y flotación suave.
class LotteryBall extends StatefulWidget {
  final String number;
  final double size;
  final bool dark;
  final double floatPhase;

  const LotteryBall({
    super.key,
    required this.number,
    this.size = 84,
    this.dark = false,
    this.floatPhase = 0,
  });

  @override
  State<LotteryBall> createState() => _LotteryBallState();
}

class _LotteryBallState extends State<LotteryBall>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 5),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.size;
    final colors = widget.dark
        ? const [Color(0xFF3A3A4A), Color(0xFF16161F), Color(0xFF07070B)]
        : const [Color(0xFFFFF4C2), WebPalette.gold, Color(0xFF6E5200)];

    // RepaintBoundary: la flotación solo repinta la balota, no su contenedor.
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, child) {
          final a = _c.value * math.pi * 2 + widget.floatPhase;
          return Transform.translate(
            offset: Offset(0, math.sin(a) * s * 0.08),
            child: Transform.rotate(angle: math.sin(a) * 0.06, child: child),
          );
        },
        child: Container(
          width: s,
          height: s,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              center: const Alignment(-0.35, -0.4),
              radius: 0.95,
              colors: colors,
              stops: const [0, 0.55, 1],
            ),
            boxShadow: [
              BoxShadow(
                color: (widget.dark ? Colors.black : WebPalette.gold)
                    .withValues(alpha: 0.45),
                blurRadius: s * 0.4,
                offset: Offset(0, s * 0.18),
              ),
            ],
          ),
          child: Center(
            child: Container(
              width: s * 0.56,
              height: s * 0.56,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: widget.dark ? const Color(0xFF0B0B10) : Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.25),
                    blurRadius: 6,
                  ),
                ],
              ),
              alignment: Alignment.center,
              padding: EdgeInsets.all(s * 0.07),
              // FittedBox: 4 cifras y Quinta siempre en una sola línea.
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: BallNumberText(
                  widget.number,
                  style: WebPalette.display(
                    s * 0.24,
                    weight: FontWeight.w800,
                    color: widget.dark
                        ? WebPalette.goldLight
                        : const Color(0xFF231A00),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Número de juego. En Quinta ("1234-5") el último dígito va en rojo.
class BallNumberText extends StatelessWidget {
  final String text;
  final TextStyle style;
  const BallNumberText(this.text, {super.key, required this.style});

  static const Color quintaRed = Color(0xFFE53935);

  @override
  Widget build(BuildContext context) {
    final i = text.lastIndexOf('-');
    if (i <= 0 || i == text.length - 1) {
      return Text(text, maxLines: 1, softWrap: false, style: style);
    }
    return Text.rich(
      TextSpan(
        style: style,
        children: [
          TextSpan(text: text.substring(0, i)),
          TextSpan(
            text: text.substring(i + 1),
            style: style.copyWith(color: quintaRed),
          ),
        ],
      ),
      maxLines: 1,
      softWrap: false,
    );
  }
}
