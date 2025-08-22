import 'package:flutter/material.dart';
import 'animated_ball.dart'; // ajusta ruta si aplica

class BigBallOverlay extends StatelessWidget {
  final int? number;

  const BigBallOverlay({super.key, required this.number});

  @override
  Widget build(BuildContext context) {
    if (number == null) return const SizedBox.shrink();
    return Align(
      alignment: Alignment.center,
      child: Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(89),
              blurRadius: 25,
              spreadRadius: 4,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: AnimatedBall(
          finalNumber: number!,
          duration: const Duration(milliseconds: 300),
          size: 160,
          enableAnimation: false,
        ),
      ),
    );
  }
}
