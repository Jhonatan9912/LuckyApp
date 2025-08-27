import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:base_app/presentation/providers/subscription_provider.dart';

class PaywallScreen extends StatefulWidget {
  const PaywallScreen({super.key});
  @override
  State<PaywallScreen> createState() => _PaywallScreenState();
}

class _PaywallScreenState extends State<PaywallScreen> {
  bool _purchasing = false;
  String? _message;

  late final SubscriptionProvider _subs;

  @override
  void initState() {
    super.initState();
    _subs = Provider.of<SubscriptionProvider>(context, listen: false);
    _bootstrapPaywall();
  }

  Future<void> _bootstrapPaywall() async {
    // ⚠️ Solo configurar billing. NO hagas refresh aquí.
    await _subs.configureBilling();
    if (!mounted) return;
    setState(() {}); // opcional, por si quieres refrescar el priceString
  }

  Future<void> _purchaseMonthly() async {
    final subs = context.read<SubscriptionProvider>();
    final nav = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);

    setState(() {
      _purchasing = true;
      _message = null;
    });

    // Dispara la compra. El estado real llega por purchaseStream.
    final ok = await subs.buyPro();

    setState(() {
      _purchasing = false;
    });

    // No llames refresh aquí; el provider ya hará refresh al recibir 'purchased'
    if (subs.isPremium) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Suscripción PRO activada')),
      );
      nav.maybePop();
    } else {
      setState(() {
        _message = ok
            ? 'Compra procesada, verificando activación…'
            : 'No se pudo completar la compra.';
      });
    }
  }

  Future<void> _restore() async {
    final subs = context.read<SubscriptionProvider>();
    final nav = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);

    // Esto dispara eventos 'restored' -> el provider hará refresh.
    await subs.restore();

    if (subs.isPremium) {
      messenger.showSnackBar(
        const SnackBar(content: Text('PRO restaurado correctamente')),
      );
      if (mounted) nav.maybePop();
    } else {
      setState(() {
        _message = 'No se encontraron compras para restaurar.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final subs = context.watch<SubscriptionProvider>();
    final isPro = subs.isPremium;
    final loading = subs.loading;
    final price = subs.priceString;

    final title = isPro ? 'Tienes PRO activo' : 'Mejora a PRO';
    final subtitle = isPro
        ? 'Gracias por tu suscripción.'
        : (price != null
              ? 'Accede a PRO por $price / mes'
              : 'Selecciona tu plan');

    // Auto-cerrar si ya se activó PRO mientras estamos en esta pantalla
    if (isPro) {
      // Evita múltiples pops con microtask
      final nav = Navigator.of(context); // captura ANTES del async gap
      Future.microtask(() {
        if (!mounted) return;
        nav.maybePop();
      });
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Pro')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: loading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.headlineSmall),
                  const SizedBox(height: 8),
                  Text(subtitle),
                  const SizedBox(height: 24),

                  if (!isPro)
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: _purchasing ? null : _purchaseMonthly,
                        child: Text(
                          _purchasing
                              ? 'Procesando...'
                              : 'Comprar PRO (${price ?? 'mensual'})',
                        ),
                      ),
                    ),

                  if (isPro)
                    const Row(
                      children: [
                        Icon(Icons.check_circle, color: Colors.green),
                        SizedBox(width: 8),
                        Text('PRO activo'),
                      ],
                    ),

                  const SizedBox(height: 12),
                  OutlinedButton(
                    onPressed: _restore,
                    child: const Text('Restaurar compras'),
                  ),

                  const Spacer(),
                  if (_message != null) ...[
                    const Divider(),
                    Text(
                      _message!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ],
                ],
              ),
      ),
    );
  }
}
