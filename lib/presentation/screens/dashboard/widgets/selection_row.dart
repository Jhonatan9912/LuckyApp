import 'package:flutter/material.dart';
import 'animated_ball.dart';
import 'package:base_app/core/utils/lottery_number_format.dart';

class SelectionRow extends StatelessWidget {
  final List<int> balls;
  final int digits;

  const SelectionRow({
    super.key,
    required this.balls,
    this.digits = 3,
  });

  @override
  Widget build(BuildContext context) {
    final bool isTwoDigits = digits == 2;
    final bool isFourDigits = digits == 4;
    final bool isQuinta = digits == 5;

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth;

        final count = balls.length.clamp(0, 5);

        const spacing = 12.0;

        final double minBallSize = isQuinta
            ? 56.0
            : (isFourDigits ? 52.0 : (isTwoDigits ? 44.0 : 48.0));

        final double maxBallSize = isQuinta
            ? 78.0
            : (isFourDigits ? 72.0 : (isTwoDigits ? 60.0 : 65.0));

        final double availableForBalls = maxWidth.clamp(80.0, maxWidth);

        // Ancho total ocupado solo por los espacios
        final double totalSpacing = spacing * (count - 1);

        // Tamaño ideal que le “toca” a cada balota
        final double rawSize =
            (availableForBalls - totalSpacing) / count.clamp(1, 5);

        // Lo limitamos a un rango razonable
        final double ballSize = rawSize.clamp(minBallSize, maxBallSize);

        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Wrap para que NUNCA haya overflow horizontal
            Expanded(
              child: Center(
                child: Wrap(
                  alignment: WrapAlignment.center,
                  spacing: spacing,
                  runSpacing: 8,
                  children: balls.asMap().entries.map((entry) {
                    final index = entry.key;
                    final number = entry.value;

                    return TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0.0, end: 1.0),
                      duration: Duration(milliseconds: 300 + index * 100),
                      builder: (context, value, child) {
                        return Opacity(
                          opacity: value,
                          child: Transform.scale(
                            scale: value,
child: AnimatedBall(
  finalNumber: number,
  duration: const Duration(milliseconds: 300),
  size: ballSize,
  enableAnimation: false,
  digits: digits, // 3 / 4 / 5
),

                          ),
                        );
                      },
                    );
                  }).toList(),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _QuintaMiniBall extends StatelessWidget {
  final String txt;
  final double size;

  const _QuintaMiniBall({
    required this.txt,
    required this.size,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            txt,
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              letterSpacing: 0.3,
            ),
          ),
        ),
      ),
    );
  }
}
