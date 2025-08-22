import 'package:flutter/material.dart';

class ActionButtons extends StatelessWidget {
  final VoidCallback? onAdd;
  final VoidCallback? onRetry;
  final bool isSaving;
  /// Cuando es true, se muestra solo el botón "VOLVER A INTENTAR".
  final bool showRetryOnly;

  const ActionButtons({
    super.key,
    this.onAdd,
    this.onRetry,
    this.isSaving = false,
    this.showRetryOnly = false,
  });

  @override
  Widget build(BuildContext context) {
    // 🔒 Mientras se reserva/guarda: oculta ambos botones
    if (isSaving) return const SizedBox.shrink();

    // ✅ Mostrar solo "VOLVER A INTENTAR" (post-reserva exitosa)
    if (showRetryOnly) {
      if (onRetry == null) return const SizedBox.shrink();
      return ElevatedButton(
        onPressed: onRetry,
        style: ElevatedButton.styleFrom(
          shape: const CircleBorder(),
          padding: const EdgeInsets.all(16),
          backgroundColor: Colors.deepPurple, // morado corporativo
          foregroundColor: Colors.white,
        ),
        child: const Icon(Icons.refresh),
      );
    }

    // Estado normal: RESERVAR + VOLVER A INTENTAR (si existen callbacks)
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (onAdd != null) ...[
          ElevatedButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.bookmark_add),
            label: const Text("RESERVAR"),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange, // 🔸 primario de acción
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            ),
          ),
          const SizedBox(width: 16),
        ],
        if (onRetry != null)
          ElevatedButton(
            onPressed: onRetry,
            style: ElevatedButton.styleFrom(
              shape: const CircleBorder(),
              padding: const EdgeInsets.all(16),
              backgroundColor: Colors.deepPurple, // 🟣 secundario
              foregroundColor: Colors.white,
            ),
            child: const Icon(Icons.refresh),
          ),
      ],
    );
  }
}
