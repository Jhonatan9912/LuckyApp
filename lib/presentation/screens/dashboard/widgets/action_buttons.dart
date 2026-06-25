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
      return _RetryButton(onRetry: onRetry!);
    }

    // Estado normal: RESERVAR (si es PRO) / MEJORAR A PRO (si NO es PRO) + RETRY (opcional)
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (onAdd != null) ...[
          isPremium
              ? _ReserveButton(onAdd: onAdd!)
              : OutlinedButton.icon(
                  onPressed: onGoPro,
                  icon: const Icon(Icons.workspace_premium),
                  label: const Text('Mejorar a PRO'),
                ),
          const SizedBox(width: 16),
        ],
        if (onRetry != null)
          _RetryButton(onRetry: onRetry!),
      ],
    );
  }
}

class _ReserveButton extends StatelessWidget {
  final VoidCallback onAdd;
  const _ReserveButton({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onAdd,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFFD4AF37), Color(0xFFF5C842), Color(0xFFD4AF37)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(28),
          boxShadow: const [
            BoxShadow(
              color: Color(0x55D4AF37),
              blurRadius: 16,
              spreadRadius: 1,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.bookmark_add, color: Color(0xFF0A0A0A), size: 20),
            SizedBox(width: 8),
            Text(
              'RESERVAR',
              style: TextStyle(
                color: Color(0xFF0A0A0A),
                fontWeight: FontWeight.w900,
                fontSize: 15,
                letterSpacing: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RetryButton extends StatelessWidget {
  final VoidCallback onRetry;
  const _RetryButton({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onRetry,
      child: Container(
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: const Color(0xFF252318),
          border: Border.all(color: const Color(0xFFD4AF37), width: 1.5),
          boxShadow: const [
            BoxShadow(
              color: Color(0x33D4AF37),
              blurRadius: 10,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: const Icon(Icons.refresh, color: Color(0xFFD4AF37), size: 22),
      ),
    );
  }
}
