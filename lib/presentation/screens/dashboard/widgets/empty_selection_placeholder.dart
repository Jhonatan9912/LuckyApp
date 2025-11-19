import 'package:flutter/material.dart';

class EmptySelectionPlaceholder extends StatelessWidget {
  final int digits; // 👈 NUEVO

  const EmptySelectionPlaceholder({
    super.key,
    required this.digits,
  });

  @override
  Widget build(BuildContext context) {
    // valores distintos para 3 y 4 cifras
    final double yOffset   = digits == 4 ? -45 : -50;
    final double size      = digits == 4 ? 180 : 180;

    return Transform.translate(
      offset: Offset(0, yOffset),
      child: Center(
        child: Image.asset(
          'assets/images/empty_placeholder.png',
          width: size,
          height: size,
          fit: BoxFit.contain,
        ),
      ),
    );
  }
}
