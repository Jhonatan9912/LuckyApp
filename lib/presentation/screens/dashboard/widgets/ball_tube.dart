import 'package:flutter/material.dart';
import 'animated_ball.dart';

class BallTube extends StatelessWidget {
  final List<int> numbers;
  final bool animating;
  final int digits; // 3 o 4

  const BallTube({
    super.key,
    required this.numbers,
    required this.animating,
    this.digits = 3,
  });

  @override
  Widget build(BuildContext context) {
final bool isFourDigits = digits == 4;

// Tamaño del tubo
final double tubeWidth  = isFourDigits ? 660 : 600;   // más ancho en 4 cifras
final double tubeHeight = isFourDigits ? 230 : 200;   // más alto en 4 cifras

// Tamaño de las bolas
final double ballSize = isFourDigits ? 54 : 45;       // bola más grande
final double spacing  = isFourDigits ? 3 : 4;

const double ballYOffset = -6;


    return SizedBox(
      width: tubeWidth,
      height: tubeHeight,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Image.asset(
            'assets/images/tube.png',
            width: tubeWidth,
            height: tubeHeight,
            fit: BoxFit.fill,
          ),
          Positioned(
            top: tubeHeight / 2 - ballSize / 2 + ballYOffset,
            left: 20,
            right: 20,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: _buildBallRow(numbers, ballSize, spacing, digits),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildBallRow(
    List<int> numbers,
    double ballSize,
    double spacing,
    int digits,
  ) {
    final row = <Widget>[];

    for (int i = 0; i < numbers.length; i++) {
      final number = numbers[i];

      row.add(
        animating
            ? AnimatedBall(
                finalNumber: number,
                duration: Duration(seconds: 1 + i),
                size: ballSize,
                digits: digits, // 👈 pasa cuántas cifras
              )
            : _buildStaticBall(number, ballSize, digits),
      );

      if (i != numbers.length - 1) {
        row.add(SizedBox(width: spacing));
      }
    }

    return row;
  }

  Widget _buildStaticBall(int number, double size, int digits) {
    final isFourDigits = digits == 4;

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Image.asset(
            'assets/images/ball.png',
            width: size,
            height: size,
            fit: BoxFit.contain,
          ),
          Text(
            number.toString().padLeft(digits, '0'),
            style: TextStyle(
              fontSize: isFourDigits ? 16 : 18, // 👈 un poquito más pequeña en 4
              fontWeight: FontWeight.bold,
              color: Colors.black,
            ),
          ),
        ],
      ),
    );
  }
}
