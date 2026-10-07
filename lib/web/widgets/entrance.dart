// lib/web/widgets/entrance.dart
import 'package:flutter/material.dart';

/// Aparición con desvanecido y desplazamiento, con retraso opcional
/// para crear animaciones escalonadas.
class Entrance extends StatefulWidget {
  final Widget child;
  final Duration delay;
  final Offset from;

  const Entrance({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.from = const Offset(0, 0.08),
  });

  @override
  State<Entrance> createState() => _EntranceState();
}

class _EntranceState extends State<Entrance>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  );
  late final Animation<double> _curve = CurvedAnimation(
    parent: _c,
    curve: Curves.easeOutCubic,
  );

  @override
  void initState() {
    super.initState();
    Future.delayed(widget.delay, () {
      if (mounted) _c.forward();
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _curve,
      child: SlideTransition(
        position: Tween(begin: widget.from, end: Offset.zero).animate(_curve),
        child: widget.child,
      ),
    );
  }
}
