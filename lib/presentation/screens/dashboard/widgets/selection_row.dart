import 'package:flutter/material.dart';
import 'animated_ball.dart';

class SelectionRow extends StatelessWidget {
  final List<int> balls;
  final bool showActions;
  final VoidCallback onClear;
  final int digits; // 👈 NUEVO

  const SelectionRow({
    super.key,
    required this.balls,
    required this.showActions,
    required this.onClear,
    this.digits = 3,
  });

  @override
  Widget build(BuildContext context) {
    final bool isFourDigits = digits == 4;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          ...balls.asMap().entries.map((entry) {
            final index = entry.key;
            final number = entry.value;
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6.0),
              child: TweenAnimationBuilder<double>(
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
                        size: isFourDigits ? 72 : 65, // 👈 un poco más grande
                        enableAnimation: false,
                        digits: digits, // 👈 respeta 3/4 cifras
                      ),
                    ),
                  );
                },
              ),
            );
          }),
          if (showActions) ...[
            const SizedBox(width: 12),
            IconButton(
              icon: const Icon(Icons.delete, size: 28, color: Colors.red),
              onPressed: onClear,
            ),
          ],
        ],
      ),
    );
  }
}
