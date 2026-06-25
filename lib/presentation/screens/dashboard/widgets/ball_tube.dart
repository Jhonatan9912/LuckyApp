import 'package:flutter/material.dart';
import 'animated_ball.dart';
import 'package:base_app/core/utils/lottery_number_format.dart';
import 'dart:async';
import 'dart:math';

class BallTube extends StatelessWidget {
  final List<int> numbers;
  final bool animating;
  final int digits;

  const BallTube({
    super.key,
    required this.numbers,
    required this.animating,
    this.digits = 3,
  });

  @override
  Widget build(BuildContext context) {
    final bool isTwoDigits = digits == 2;
    final bool isFourDigits = digits == 4;
    final bool isQuinta = digits == 5;

    final double tubeWidth = isQuinta
        ? 900
        : (isFourDigits ? 660 : (isTwoDigits ? 540 : 600));

    final double tubeHeight = isQuinta
        ? 210
        : (isFourDigits ? 180 : (isTwoDigits ? 150 : 160));

    final double ballSize = isQuinta
        ? 57
        : (isFourDigits ? 54 : (isTwoDigits ? 42 : 45));

    final double spacing = isQuinta
        ? 6
        : (isFourDigits ? 3 : (isTwoDigits ? 6 : 4));

    const double baseYOffset = -6;
    final double ballYOffset = isQuinta ? (baseYOffset - 2) : baseYOffset;

    return SizedBox(
      width: tubeWidth,
      height: tubeHeight,
child: Stack(
  alignment: Alignment.topCenter,
  children: [

Image.asset(
  'assets/images/tube.png',
  width: tubeWidth,
  height: tubeHeight,
  fit: BoxFit.fill,
  alignment: Alignment.topCenter, // ✅ agrega esta línea
),

          Positioned(
            top: tubeHeight / 2 - ballSize / 2 + ballYOffset,
            left: 20,
            right: 20,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: _buildBallRow(
                numbers: numbers,
                ballSize: ballSize,
                spacing: spacing,
                isQuinta: isQuinta,
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildBallRow({
    required List<int> numbers,
    required double ballSize,
    required double spacing,
    required bool isQuinta,
  }) {
    final row = <Widget>[];

    for (int i = 0; i < numbers.length; i++) {
      final int number = numbers[i];

row.add(
  AnimatedBall(
    finalNumber: number,
    duration: Duration(seconds: 1 + i),
    size: ballSize,
    digits: digits,              // 👈 ahora también puede ser 5
    enableAnimation: animating,
  ),
);


      if (i != numbers.length - 1) {
        row.add(SizedBox(width: spacing));
      }
    }

    return row;
  }
}
