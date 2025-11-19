import 'package:flutter/material.dart';
import 'animated_ball.dart';

class SelectionRow extends StatelessWidget {
  final List<int> balls;
  final bool showActions;
  final VoidCallback onClear;
  final int digits; // 👈 3 o 4

  const SelectionRow({
    super.key,
    required this.balls,
    required this.showActions,
    required this.onClear,
    this.digits = 3,
  });

  @override
  Widget build(BuildContext context) {
    final bool isFourDigits = digits == 4;

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth;

        // Cuántas balotas mostramos (máx 5 por si acaso)
        final count = balls.length.clamp(0, 5);

        // Espaciado entre balotas
        const spacing = 12.0;

        // Tamaños mínimos / máximos
        final double minBallSize = isFourDigits ? 52.0 : 48.0;
        final double maxBallSize = isFourDigits ? 72.0 : 65.0;

        // Si hay icono de borrar, reservamos algo de ancho para él
        final double actionsWidth = showActions ? 56.0 : 0.0;

        // Ancho restante disponible para las balotas
        final double availableForBalls =
            (maxWidth - actionsWidth).clamp(80.0, maxWidth);

        // Ancho total ocupado solo por los espacios
        final double totalSpacing = spacing * (count - 1);

        // Tamaño ideal que le “toca” a cada balota
        final double rawSize =
            (availableForBalls - totalSpacing) / count.clamp(1, 5);

        // Lo limitamos a un rango razonable
        final double ballSize =
            rawSize.clamp(minBallSize, maxBallSize);

        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Wrap para que NUNCA haya overflow horizontal
            Expanded(
              child: Center(
                child: Wrap(
                  alignment: WrapAlignment.center,
                  spacing: spacing,
                  runSpacing: 8,
                  children: balls.asMap().entries.map((entry) {
                    final index = entry.key;
                    final number = entry.value;
                    return TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0.0, end: 1.0),
                      duration: Duration(milliseconds: 300 + index * 100),
                      builder: (context, value, child) {
                        return Opacity(
                          opacity: value,
                          child: Transform.scale(
                            scale: value,
                            child: AnimatedBall(
                              finalNumber: number,
                              duration: const Duration(milliseconds: 300),
                              size: ballSize,
                              enableAnimation: false,
                              digits: digits, // 👈 respeta 3/4 cifras
                            ),
                          ),
                        );
                      },
                    );
                  }).toList(),
                ),
              ),
            ),

            if (showActions) ...[
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.delete, size: 28, color: Colors.red),
                onPressed: onClear,
              ),
            ],
          ],
        );
      },
    );
  }
}
