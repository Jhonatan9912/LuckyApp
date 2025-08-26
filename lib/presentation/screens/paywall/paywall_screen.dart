import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:provider/provider.dart';

import 'package:base_app/presentation/providers/subscription_provider.dart';

class PaywallScreen extends StatefulWidget {
  const PaywallScreen({super.key});

  @override
  State<PaywallScreen> createState() => _PaywallScreenState();
}

class _PaywallScreenState extends State<PaywallScreen> {
  bool _loading = true;
  bool _purchasing = false;
  Package? _monthly;
  String? _price;
  bool _isPro = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    _loadOfferings();
    _loadCustomerInfo();

    // Escucha cambios de entitlements (p.ej., si RC actualiza en caliente)
    Purchases.addCustomerInfoUpdateListener((info) {
      final isPro = info.entitlements.active.containsKey('pro');
      if (mounted) setState(() => _isPro = isPro);
    });
  }

  Future<void> _loadOfferings() async {
    try {
      final offerings = await Purchases.getOfferings();
      final current = offerings.current;

      Package? monthly;
      if (current != null) {
        // Intenta por id 'monthly', si no existe toma el primero
        monthly = current.availablePackages
            .where((p) => p.identifier == 'monthly')
            .cast<Package?>()
            .firstOrNull;
        monthly ??= current.availablePackages.isNotEmpty
            ? current.availablePackages.first
            : null;
      }

      String? price;
      if (monthly != null) {
        price = monthly.storeProduct.priceString;
      }

      if (mounted) {
        setState(() {
          _monthly = monthly;
          _price = price;
          _loading = false;
          _message = monthly == null
              ? 'No hay paquetes disponibles en el offering.'
              : null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _message = 'Error cargando offering: $e';
        });
      }
    }
  }

  Future<void> _loadCustomerInfo() async {
    try {
      final info = await Purchases.getCustomerInfo();
      final isPro = info.entitlements.active.containsKey('pro');
      if (mounted) setState(() => _isPro = isPro);
    } catch (_) {
      // Ignora error inicial
    }
  }

  Future<void> _purchaseMonthly() async {
    if (_monthly == null) return;

    // Captura dependencias ANTES de await (buenas prácticas)
    final subs = context.read<SubscriptionProvider>();
    final nav = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);

    setState(() {
      _purchasing = true;
      _message = null;
    });

    try {
      // v9: PurchaseResult con customerInfo
      final result = await Purchases.purchasePackage(_monthly!);
      final info = result.customerInfo;
      final hasPro = info.entitlements.active.containsKey('pro');

      // 🚀 Sincroniza con tu backend y refresca UI
      await subs.refresh(force: true);

      if (mounted) {
        setState(() {
          _isPro = hasPro;
          _message = hasPro
              ? '¡Compra exitosa! PRO activado.'
              : 'Compra realizada, pero PRO aún no aparece activo.';
        });
      }

      // Si quedaste PRO, cierra el paywall (opcional)
      if (hasPro) {
        messenger.showSnackBar(
          const SnackBar(content: Text('Suscripción PRO activada')),
        );
        if (mounted) nav.maybePop();
      }
    } on PlatformException catch (e) {
      final code = PurchasesErrorHelper.getErrorCode(e);
      if (mounted) {
        setState(() {
          _message = code == PurchasesErrorCode.purchaseCancelledError
              ? 'Compra cancelada.'
              : 'Error de compra: $code';
        });
      }
    } catch (e) {
      if (mounted) setState(() => _message = 'Error de compra: $e');
    } finally {
      if (mounted) setState(() => _purchasing = false);
    }
  }

  Future<void> _restore() async {
    // Captura dependencias ANTES de await
    final subs = context.read<SubscriptionProvider>();
    final nav = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);

    try {
      final info = await Purchases.restorePurchases();
      final hasPro = info.entitlements.active.containsKey('pro');

      // 🚀 Refresca backend → provider
      await subs.refresh(force: true);

      if (mounted) {
        setState(() {
          _isPro = hasPro;
          _message = hasPro
              ? 'Compras restauradas: PRO activo.'
              : 'No se encontraron compras para restaurar.';
        });
      }

      if (hasPro) {
        messenger.showSnackBar(
          const SnackBar(content: Text('PRO restaurado correctamente')),
        );
        if (mounted) nav.maybePop();
      }
    } catch (e) {
      if (mounted) setState(() => _message = 'Error al restaurar: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = _isPro ? 'Tienes PRO activo' : 'Mejora a PRO';
    final subtitle = _isPro
        ? 'Gracias por tu suscripción.'
        : (_price != null
            ? 'Accede a PRO por $_price / mes'
            : 'Selecciona tu plan');

    return Scaffold(
      appBar: AppBar(title: const Text('Pro')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.headlineSmall),
                  const SizedBox(height: 8),
                  Text(subtitle),
                  const SizedBox(height: 24),

                  if (!_isPro && _monthly != null)
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: _purchasing ? null : _purchaseMonthly,
                        child: Text(
                          _purchasing
                              ? 'Procesando...'
                              : 'Comprar PRO (${_price ?? 'mensual'})',
                        ),
                      ),
                    ),

                  if (_isPro)
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

// helper para firstOrNull sin deps extra
extension _IterableX<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
