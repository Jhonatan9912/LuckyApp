import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';

class AnimatedBall extends StatefulWidget {
  final int finalNumber;
  final Duration duration;
  final double size;
  final bool enableAnimation;

  const AnimatedBall({
    super.key,
    required this.finalNumber,
    required this.duration,
    required this.size,
    this.enableAnimation = true,
  });

  @override
  State<AnimatedBall> createState() => _AnimatedBallState();
}

class _AnimatedBallState extends State<AnimatedBall>
    with SingleTickerProviderStateMixin {
  Timer? _timer;                           // ← nullable
  late int _currentNumber;
  late AnimationController _scaleController;

  @override
  void initState() {
    super.initState();

    _currentNumber = widget.enableAnimation
        ? _random3Digit()
        : widget.finalNumber;

    _scaleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
      lowerBound: 1.0,
      upperBound: 1.3,
      value: 1.0,                          // ← arranca estable en 1.0
    );

    if (widget.enableAnimation) {
      _startAnimation();
    }
  }

  void _startAnimation() {
    _timer = Timer.periodic(const Duration(milliseconds: 50), (timer) {
      if (!mounted) return;
      setState(() => _currentNumber = _random3Digit());
    });

    Future.delayed(widget.duration, () {
      _timer?.cancel();                     // ← segura
      if (!mounted) return;
      setState(() => _currentNumber = widget.finalNumber);

      // efecto de escala
      _scaleController.forward().then((_) {
        if (mounted) _scaleController.reverse();
      });
    });
  }

  int _random3Digit() => Random().nextInt(1000);

  @override
  void dispose() {
    _timer?.cancel();                       // ← segura aunque no exista
    _scaleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
              _currentNumber.toString().padLeft(3, '0'),
              style: const TextStyle(
                fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
