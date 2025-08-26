import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:base_app/presentation/providers/subscription_provider.dart';

/// Gate sencillo para bloquear contenido PRO.
/// - Si el usuario es premium: muestra [child].
/// - Si NO es premium: muestra [fallback] o un teaser con botón a /pro.
class PremiumGate extends StatelessWidget {
  final Widget child;
  final Widget? fallback;
  final VoidCallback? onGoPro;

  const PremiumGate({
    super.key,
    required this.child,
    this.fallback,
    this.onGoPro,
  });

  @override
  Widget build(BuildContext context) {
    final subs = context.watch<SubscriptionProvider>();

    // Mientras carga, mostramos un placeholder no intrusivo
    if (subs.loading) {
      return const Center(child: Padding(
        padding: EdgeInsets.all(12),
        child: CircularProgressIndicator(strokeWidth: 2),
      ));
    }

    // Si es premium, deja pasar
    if (subs.isPremium) return child;

    // Si no es premium, usa fallback o el teaser por defecto
    return fallback ?? const _DefaultPaywallTeaser();
  }
}

/// Teaser por defecto: texto + botón para abrir paywall + restaurar
class _DefaultPaywallTeaser extends StatelessWidget {
  const _DefaultPaywallTeaser();

  @override
  Widget build(BuildContext context) {
    final subs = context.read<SubscriptionProvider>();

    return Container(
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.amber.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.amber.shade200),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Contenido PRO',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          const Text(
            'Mejora a PRO para desbloquear esta sección.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              FilledButton.icon(
                onPressed: () {
                  Navigator.of(context).pushNamed('/pro');
                },
                icon: const Icon(Icons.workspace_premium),
                label: const Text('Mejorar a PRO'),
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed: () async {
                  await subs.refresh(force: true); // intenta restaurar desde backend
                  if (context.mounted && subs.isPremium) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Suscripción restaurada')),
                    );
                  }
                },
                child: const Text('Restaurar'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
