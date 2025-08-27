import 'dart:async';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:shared_preferences/shared_preferences.dart';

class BillingService {
  BillingService._();
  // Singleton simple
  static final instance = BillingService._();

  final InAppPurchase _iap = InAppPurchase.instance;

  /// ⚠️ Cambia por el productId EXACTO de tu suscripción en Play Console
  /// (solo el ID del producto, NO el base plan / offer).
  static const Set<String> _kProductIds = {'cm_suscripcion'};

  // Estado
  bool available = false;
  bool isPremium = false;
  List<ProductDetails> products = [];
  StreamSubscription<List<PurchaseDetails>>? _sub;

  Future<void> init() async {
    available = await _iap.isAvailable();
    await _restoreLocalFlag();
    if (!available) return;

    // Escuchar actualizaciones de compra
    _sub ??= _iap.purchaseStream.listen(
      _onPurchaseUpdate,
      onDone: () => _sub?.cancel(),
      onError: (_) {}, // puedes loguear si quieres
    );

    await queryProducts();
    // Útil para testers/sandbox
    await restorePurchases();
  }

  Future<void> dispose() async {
    await _sub?.cancel();
  }

  Future<void> queryProducts() async {
    final resp = await _iap.queryProductDetails(_kProductIds);
    products = resp.productDetails;
  }

  /// Inicia la compra del producto configurado.
  Future<void> buyMonthly() async {
    if (products.isEmpty) await queryProducts();

    final product = products.firstWhere(
      (p) => p.id == _kProductIds.first,
      orElse: () => throw Exception('Producto no encontrado en Play Console'),
    );

    final params = PurchaseParam(productDetails: product);
    await _iap.buyNonConsumable(purchaseParam: params);
  }

  /// Restaura compras (reinstalaciones / testers).
  Future<void> restorePurchases() async {
    await _iap.restorePurchases();
  }

  Future<void> _onPurchaseUpdate(List<PurchaseDetails> purchases) async {
    for (final p in purchases) {
      switch (p.status) {
        case PurchaseStatus.pending:
          // estado intermedio
          break;

        case PurchaseStatus.purchased:
          // En producción, valida el recibo en tu backend antes de marcar PRO
          await _markPremium(true);
          await _complete(p); // acknowledge/finish
          break;

        case PurchaseStatus.restored:
          await _markPremium(true);
          await _complete(p);
          break;

        case PurchaseStatus.error:
          // puedes loguear p.error
          break;

        case PurchaseStatus.canceled:
          break;
      }
    }
  }

  Future<void> _complete(PurchaseDetails purchase) async {
    if (purchase.pendingCompletePurchase) {
      await _iap.completePurchase(purchase);
    }
  }

  Future<void> _markPremium(bool value) async {
    isPremium = value;
    final sp = await SharedPreferences.getInstance();
    await sp.setBool('is_premium', value);
  }

  Future<void> _restoreLocalFlag() async {
    final sp = await SharedPreferences.getInstance();
    isPremium = sp.getBool('is_premium') ?? false;
  }
}
