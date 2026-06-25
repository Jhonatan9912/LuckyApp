import 'package:flutter/material.dart';
import 'animated_ball.dart';
import 'package:base_app/core/utils/lottery_number_format.dart';

class BigBallOverlay extends StatelessWidget {
  final int? number;
  final int digits; // 3, 4 o 5 (quinta)

  const BigBallOverlay({
    super.key,
    required this.number,
    required this.digits,
  });

  @override
  Widget build(BuildContext context) {
    if (number == null) return const SizedBox.shrink();

    final txt = formatGameNumber(number!, digits); // para quinta debe ser "0000-0"

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
  digits: digits, // 3 / 4 / 5
  duration: const Duration(milliseconds: 300),
  size: 160,
  enableAnimation: false,
),

      ),
    );
  }
}

class _QuintaBallText extends StatelessWidget {
  final String txt; // "0000-0"
  final double size;

  const _QuintaBallText({
    required this.txt,
    required this.size,
  });

  @override
  Widget build(BuildContext context) {
    // Seguridad: si por alguna razón llega sin guion, lo tratamos como "00000"
    final safe = txt.contains('-') && txt.length >= 6
        ? txt
        : _fallbackToQuintaFormat(txt);

    final left = safe.substring(0, 5); // "0000-"
    final last = safe.substring(5); // "0"

    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white,
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: RichText(
          textAlign: TextAlign.center,
          text: TextSpan(
            style: const TextStyle(
              fontSize: 34,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.5,
              color: Colors.black,
            ),
            children: [
              TextSpan(text: left),
              const TextSpan(text: ''), // placeholder
              TextSpan(
                text: last,
                style: const TextStyle(color: Colors.red),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _fallbackToQuintaFormat(String any) {
    // si llega "123" -> "0000-0" aprox
    final raw = any.replaceAll('-', '').padLeft(5, '0');
    return '${raw.substring(0, 4)}-${raw.substring(4)}';
  }
}
