import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';

class AnimatedBall extends StatefulWidget {
  final int finalNumber;
  final Duration duration;
  final double size;
  final bool enableAnimation;
  final int digits; // 👈 NUEVO: 3 o 4

  const AnimatedBall({
    super.key,
    required this.finalNumber,
    required this.duration,
    required this.size,
    this.enableAnimation = true,
    this.digits = 3,
  });

  @override
  State<AnimatedBall> createState() => _AnimatedBallState();
}

class _AnimatedBallState extends State<AnimatedBall>
    with SingleTickerProviderStateMixin {
  Timer? _timer;
  late int _currentNumber;
  late AnimationController _scaleController;

  @override
  void initState() {
    super.initState();

    _currentNumber =
        widget.enableAnimation ? _randomNumber() : widget.finalNumber;

    _scaleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
      lowerBound: 1.0,
      upperBound: 1.3,
      value: 1.0,
    );

    if (widget.enableAnimation) {
      _startAnimation();
    }
  }

  void _startAnimation() {
    _timer = Timer.periodic(const Duration(milliseconds: 50), (timer) {
      if (!mounted) return;
      setState(() => _currentNumber = _randomNumber());
    });

    Future.delayed(widget.duration, () {
      _timer?.cancel();
      if (!mounted) return;
      setState(() => _currentNumber = widget.finalNumber);

      _scaleController.forward().then((_) {
        if (mounted) _scaleController.reverse();
      });
    });
  }

  int _randomNumber() {
    final max = pow(10, widget.digits).toInt(); // 1000 ó 10000
    return Random().nextInt(max);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _scaleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isFourDigits = widget.digits == 4;

    return ScaleTransition(
      scale: _scaleController,
      child: SizedBox(
        width: widget.size,
        height: widget.size,
        child: Stack(
          alignment: Alignment.center,
          children: [
            ShaderMask(
              shaderCallback: (Rect bounds) {
                return const LinearGradient(
                  colors: [Colors.white30, Colors.transparent],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ).createShader(bounds);
              },
              blendMode: BlendMode.srcATop,
              child: Image.asset(
                'assets/images/ball.png',
                width: widget.size,
                height: widget.size,
                fit: BoxFit.contain,
              ),
            ),
            Text(
              _currentNumber.toString().padLeft(widget.digits, '0'),
              style: TextStyle(
                fontSize: isFourDigits ? 16 : 18,
                fontWeight: FontWeight.bold,
                color: Colors.black,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
