  import 'package:flutter/material.dart';
  import 'animated_ball.dart';

  class BallTube extends StatelessWidget {
    final List<int> numbers;
    final bool animating;

    const BallTube({
      super.key,
      required this.numbers,
      required this.animating,
    });

    @override
    Widget build(BuildContext context) {
      const double tubeWidth = 600;
      const double tubeHeight = 200;
      const double ballSize = 45;
      const double spacing = 4;
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
                children: _buildBallRow(numbers, ballSize, spacing),
              ),
            ),
          ],
        ),
      );
    }

    List<Widget> _buildBallRow(List<int> numbers, double ballSize, double spacing) {
      List<Widget> row = [];

      for (int i = 0; i < numbers.length; i++) {
        final number = numbers[i];

        row.add(
          animating
              ? AnimatedBall(
                  finalNumber: number,
                  duration: Duration(seconds: 1 + i),
                  size: ballSize,
                )
              : _buildStaticBall(number, ballSize),
        );

        if (i != numbers.length - 1) {
          row.add(SizedBox(width: spacing));
        }
      }

      return row;
    }

    Widget _buildStaticBall(int number, double size) {
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
              number.toString().padLeft(3, '0'),
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.black,
              ),
            ),
          ],
        ),
      );
    }
  }
