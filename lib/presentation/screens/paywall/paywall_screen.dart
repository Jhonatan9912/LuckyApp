import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:base_app/presentation/providers/subscription_provider.dart';
import 'package:url_launcher/url_launcher.dart';

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
    setState(() {}); // refresca priceString si apareció tras cargar catálogo
  }

  Future<void> _purchaseProduct(String productId) async {
    final subs = context.read<SubscriptionProvider>();
    final nav = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);

    setState(() {
      _purchasing = true;
      _message = null;
    });

    try {
      final ok = await subs.buyPro(productId: productId);

      if (subs.isPremium) {
        messenger.showSnackBar(
          const SnackBar(content: Text('Suscripción PRO activada')),
        );
        if (mounted) nav.maybePop();
      } else {
        setState(() {
          _message = ok
              ? 'Compra procesada, verificando activación…'
              : 'No se pudo completar la compra.';
        });
      }
    } catch (e) {
      setState(() {
        _message = 'Error al comprar: $e';
      });
    } finally {
      if (mounted) setState(() => _purchasing = false);
    }
  }

  Future<void> _restore() async {
    final subs = context.read<SubscriptionProvider>();
    final nav = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);

    try {
      await subs
          .restore(); // disparará restored → sync → refresh en el provider
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
    } catch (e) {
      setState(() {
        _message = 'Error al restaurar: $e';
      });
    }
  }

  Future<void> _openManage() async {
    final uri = Uri.parse(
      // ajusta sku y package si quieres algo más específico
      'https://play.google.com/store/account/subscriptions',
    );
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      // no pasa nada si falla; solo mensaje opcional
      setState(
        () => _message = 'No se pudo abrir la gestión de suscripciones.',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final subs = context.watch<SubscriptionProvider>();
    final isPro = subs.isPremium;
    final loading = subs.loading || subs.activating;
    final products = subs.products;
    final hasProducts = products.isNotEmpty;

    final title = isPro ? 'Tienes PRO activo' : 'Mejora a PRO';
    final subtitle = isPro
        ? 'Gracias por tu suscripción.'
        : (hasProducts ? 'Selecciona tu plan' : 'Cargando planes…');

    // Auto-cerrar si ya se activó PRO mientras estamos en esta pantalla
    if (isPro) {
      final nav = Navigator.of(context);
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

                  if (!isPro) ...[
                    // Un botón por cada producto disponible (20k y 60k, etc.)
                    for (final p in products) ...[
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: _purchasing
                              ? null
                              : () => _purchaseProduct(p.id),
                          child: Text(
                            _purchasing
                                ? 'Procesando...'
                                : 'Suscribirme a ${p.title} — ${p.price}',
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],

                    // Gestionar desde Play (útil para cancelar en pruebas)
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _openManage,
                        icon: const Icon(Icons.manage_accounts),
                        label: const Text(
                          'Gestionar suscripción en Google Play',
                        ),
                      ),
                    ),
                  ],

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
