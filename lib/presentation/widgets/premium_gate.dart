import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:base_app/presentation/providers/subscription_provider.dart';

class PremiumGate extends StatefulWidget {
  final Widget child;
  final Widget? fallback;
  final VoidCallback? onGoPro;
  /// Si true, muestra el child sin importar si es PRO o no (ej: modo gratis)
  final bool bypass;

  const PremiumGate({
    super.key,
    required this.child,
    this.fallback,
    this.onGoPro,
    this.bypass = false,
  });

  @override
  State<PremiumGate> createState() => _PremiumGateState();
}

class _PremiumGateState extends State<PremiumGate> {
  bool? _lastIsPremium;

  @override
  Widget build(BuildContext context) {
    if (widget.bypass) return widget.child;

    final subs = context.watch<SubscriptionProvider>();

    _lastIsPremium ??= subs.isPremium;
    if (!subs.loading) {
      _lastIsPremium = subs.isPremium;
    }

    final showPremium = _lastIsPremium == true;

    if (showPremium) return widget.child;
    return widget.fallback ?? const _DefaultPaywallTeaser();
  }
}

class _DefaultPaywallTeaser extends StatelessWidget {
  const _DefaultPaywallTeaser();

  @override
  Widget build(BuildContext context) {
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
          const Text('Contenido PRO', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          const Text('Mejora a PRO para desbloquear esta sección.', textAlign: TextAlign.center),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: () => Navigator.of(context).pushNamed('/pro'),
            icon: const Icon(Icons.workspace_premium),
            label: const Text('Mejorar a PRO'),
          ),
        ],
      ),
    );
  }
}
