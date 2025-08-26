import 'package:flutter/material.dart';

class ActionButtons extends StatelessWidget {
  final VoidCallback? onAdd;
  final VoidCallback? onRetry;
  final bool isSaving;

  /// Muestra solo "VOLVER A INTENTAR" (post-reserva exitosa).
  final bool showRetryOnly;

  /// ⬇️ NUEVO: si es true puede reservar; si es false se muestra CTA para PRO.
  final bool isPremium;

  /// ⬇️ NUEVO: acción para llevar al paywall cuando NO es PRO.
  final VoidCallback? onGoPro;

  const ActionButtons({
    super.key,
    this.onAdd,
    this.onRetry,
    this.isSaving = false,
    this.showRetryOnly = false,
    this.isPremium = false,
    this.onGoPro,
  });

  @override
  Widget build(BuildContext context) {
    // Mientras se reserva/guarda: oculta ambos botones
    if (isSaving) return const SizedBox.shrink();

    // Solo "VOLVER A INTENTAR"
    if (showRetryOnly) {
      if (onRetry == null) return const SizedBox.shrink();
      return ElevatedButton(
        onPressed: onRetry,
        style: ElevatedButton.styleFrom(
          shape: const CircleBorder(),
          padding: const EdgeInsets.all(16),
          backgroundColor: Colors.deepPurple,
          foregroundColor: Colors.white,
        ),
        child: const Icon(Icons.refresh),
      );
    }

    // Estado normal: RESERVAR (si es PRO) / MEJORAR A PRO (si NO es PRO) + RETRY (opcional)
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (onAdd != null) ...[
          isPremium
              ? ElevatedButton.icon(
                  onPressed: onAdd,
                  icon: const Icon(Icons.bookmark_add),
                  label: const Text("RESERVAR"),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
                    foregroundColor: Colors.white,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  ),
                )
              : OutlinedButton.icon(
                  onPressed: onGoPro,
                  icon: const Icon(Icons.workspace_premium),
                  label: const Text("Mejorar a PRO"),
                ),
          const SizedBox(width: 16),
        ],
        if (onRetry != null)
          ElevatedButton(
            onPressed: onRetry,
            style: ElevatedButton.styleFrom(
              shape: const CircleBorder(),
              padding: const EdgeInsets.all(16),
              backgroundColor: Colors.deepPurple,
              foregroundColor: Colors.white,
            ),
            child: const Icon(Icons.refresh),
          ),
      ],
    );
  }
}
