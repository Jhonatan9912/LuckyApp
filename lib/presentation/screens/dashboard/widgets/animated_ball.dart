import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';

class AnimatedBall extends StatefulWidget {
  final int finalNumber;
  final Duration duration;
  final double size;
  final bool enableAnimation;
  final int digits;

  // ✅ Personalización visual (se respeta para texto base)
  final Color? textColor;
  final double? textSize;

  const AnimatedBall({
    super.key,
    required this.finalNumber,
    required this.duration,
    required this.size,
    this.enableAnimation = true,
    this.digits = 3,
    this.textColor,
    this.textSize,
  });

  @override
  State<AnimatedBall> createState() => _AnimatedBallState();
}

class _AnimatedBallState extends State<AnimatedBall>
    with SingleTickerProviderStateMixin {
  Timer? _timer;
  late int _currentNumber;
  late AnimationController _scaleController;
  bool _finished = false;

  int get _maxValue => pow(10, widget.digits).toInt();

  @override
  void initState() {
    super.initState();
    _currentNumber = widget.finalNumber;

    _scaleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
      lowerBound: 1.0,
      upperBound: 1.3,
      value: 1.0,
    );

    _startIfNeeded();
  }

  @override
  void didUpdateWidget(covariant AnimatedBall oldWidget) {
    super.didUpdateWidget(oldWidget);

    final needsRestart =
        oldWidget.finalNumber != widget.finalNumber ||
        oldWidget.enableAnimation != widget.enableAnimation ||
        oldWidget.digits != widget.digits;

    if (needsRestart) {
      _timer?.cancel();
      _finished = false;
      _currentNumber = widget.finalNumber;
      _scaleController.value = 1.0;
      _startIfNeeded();
    }
  }

  void _startIfNeeded() {
    if (!widget.enableAnimation) {
      setState(() {
        _currentNumber = widget.finalNumber;
        _finished = true;
      });
      return;
    }

    final rnd = Random();

    _timer = Timer.periodic(const Duration(milliseconds: 70), (_) {
      if (!mounted || _finished) return;
      setState(() {
        _currentNumber = rnd.nextInt(_maxValue);
      });
    });

    Future.delayed(widget.duration, () {
      if (!mounted) return;
      _finished = true;
      _timer?.cancel();
      setState(() {
        _currentNumber = widget.finalNumber;
      });

      _scaleController.forward().then((_) {
        if (mounted) _scaleController.reverse();
      });
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _scaleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool isQuinta =
    widget.digits == 5 || widget.finalNumber.toString().length >= 5;


    // ✅ Quinta: fuente más grande por defecto
    final double computedFontSize =
        widget.textSize ?? (isQuinta ? 22 : (widget.digits == 4 ? 18 : 18));

    // Color base (para todo menos el último dígito en Quinta)
    final Color baseColor = widget.textColor ?? Colors.black;

    // Texto base con padding (000 / 0000 / 00000)
    final int effectiveDigits = isQuinta ? 5 : widget.digits;
final raw = _currentNumber.toString().padLeft(effectiveDigits, '0');


    // ✅ Widget del número (Text normal o RichText en Quinta)
    final Widget numberWidget = isQuinta
        ? _buildQuintaRichText(
            raw: raw,
            fontSize: computedFontSize,
            baseColor: baseColor,
          )
        : Text(
            raw,
            style: TextStyle(
              fontSize: computedFontSize,
              fontWeight: FontWeight.w900,
              color: baseColor,
              letterSpacing: effectiveDigits == 4 ? 0.4 : 0.4,

            ),
          );

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

            // ✅ Para que nunca quede microscópico, usamos FittedBox
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: numberWidget,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ✅ Quinta: "0000-0" y último dígito en rojo
  Widget _buildQuintaRichText({
    required String raw, // "00000"
    required double fontSize,
    required Color baseColor,
  }) {
    // raw tiene 5 chars, ej: "01234"
    final left = raw.substring(0, 4); // "0123"
    final last = raw.substring(4); // "4"

    return RichText(
      textAlign: TextAlign.center,
      text: TextSpan(
        style: TextStyle(
          fontSize: fontSize,
          fontWeight: FontWeight.w900,
          color: baseColor,
          letterSpacing: 0.6,
        ),
        children: [
          TextSpan(text: '$left-'), // "0123-"
          const TextSpan(
            text: '', // placeholder (no afecta)
          ),
          TextSpan(
            text: last, // "4"
            style: const TextStyle(color: Colors.red),
          ),
        ],
      ),
    );
  }
}
