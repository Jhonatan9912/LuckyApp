import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:base_app/data/api/subscriptions_api.dart';
import 'package:base_app/data/session/session_manager.dart';
import 'dart:developer' as dev;

/// Provider de suscripción usando Google Play Billing (in_app_purchase)
class SubscriptionProvider extends ChangeNotifier {
  final SubscriptionsApi api;
  final SessionManager session;
  final Duration ttl;

  SubscriptionProvider({
    required this.api,
    required this.session,
    this.ttl = const Duration(minutes: 5),
  });

  // ========= Estado público =========
  bool _loading = false;
  bool get loading => _loading;

  bool _isPremium = false;
  bool get isPremium => _isPremium;

  String _status = 'none'; // active | expired | none | not_authenticated
  String get status => _status;

  DateTime? _expiresAt;
  DateTime? get expiresAt => _expiresAt;

  DateTime? _lastFetch;
  String? _error;
  String? get error => _error;

  /// Getter para usar en Paywall
ProductDetails? get product => _product;
String? get priceString => _product?.price;

  // ========= Internos Billing =========
  final InAppPurchase _iap = InAppPurchase.instance;
  bool _billingConfigured = false;
  StreamSubscription<List<PurchaseDetails>>? _purchaseSub;

  // ⚠️ AJUSTA ESTO al productId EXACTO en Play Console (NO base plan)
  static const String _gpProductId = 'cm_suscripcion';
  ProductDetails? _product;

  // ========= Compat alias para no tocar tu app =========
  Future<void> configureRC({required String apiKey, String? appUserId}) async {
    await configureBilling();
  }

  /// Nueva forma explícita
  Future<void> configureBilling() async {
    if (_billingConfigured) return;

    final available = await _iap.isAvailable();
    if (!available) {
      dev.log('Billing no disponible (¿Play Store instalada / app desde Play? )');
      _billingConfigured = false;
      return;
    }

    // Suscripción al stream de compras
    _purchaseSub ??= _iap.purchaseStream.listen(
      _onPurchaseUpdates,
      onError: (e) => dev.log('purchaseStream error: $e'),
      onDone: () => dev.log('purchaseStream done'),
    );

    // Cargar catálogo
    await _queryProduct();

    _billingConfigured = true;
  }

  void clear() {
    _loading = false;
    _isPremium = false;
    _status = 'none';
    _expiresAt = null;
    _lastFetch = null;
    _error = null;

    _purchaseSub?.cancel();
    _purchaseSub = null;
    _billingConfigured = false;

    notifyListeners();
  }

  Future<void> refresh({bool force = false}) async {
    _error = null;

    // 1) Intentar restaurar compras (sandbox/testers)
    try {
      if (_billingConfigured) {
        await _iap.restorePurchases();
      } else {
        await configureBilling();
      }
    } catch (e) {
      dev.log('subs.refresh() restore error: $e');
    }

    // 2) Backend con TTL
    if (!force &&
        _lastFetch != null &&
        DateTime.now().difference(_lastFetch!) < ttl) {
      return;
    }

    _loading = true;
    notifyListeners();

    try {
      final token = await session.getToken();
      dev.log('subs.refresh() token presente? ${token != null && token.isNotEmpty}');

      if (token == null || token.isEmpty) {
        _isPremium = false;
        _status = 'not_authenticated';
        _expiresAt = null;
        _lastFetch = DateTime.now();
        return;
      }

      final json = await api.getStatus(token: token);
      dev.log('subs.refresh() status payload: $json');

      final fromBackendIsPremium = (json['isPremium'] == true);
      final fromBackendStatus = (json['status'] ?? 'none').toString();

      // Asegura string -> DateTime
      final String? expStr = json['expiresAt']?.toString();
      final DateTime? fromBackendExpires =
          (expStr != null && expStr.isNotEmpty) ? DateTime.tryParse(expStr) : null;

      // Si backend dice PRO o ya quedó PRO por una compra restaurada, es PRO
      final mergedPremium = _isPremium || fromBackendIsPremium;

      _isPremium = mergedPremium;
      _status = mergedPremium ? 'active' : fromBackendStatus;
      _expiresAt = _expiresAt ?? fromBackendExpires;

      _lastFetch = DateTime.now();
      dev.log('subs.refresh() result -> isPremium=$_isPremium, status=$_status, expiresAt=$_expiresAt');
    } catch (e) {
      _error = e.toString();
      dev.log('subs.refresh() backend error: $_error');
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<bool> buyPro() async {
    try {
      if (!_billingConfigured) {
        await configureBilling();
        if (!_billingConfigured) {
          throw Exception('Google Play Billing no disponible en este dispositivo.');
        }
      }

      if (_product == null) {
        await _queryProduct();
        if (_product == null) {
          throw Exception('Producto $_gpProductId no encontrado en Play Console.');
        }
      }

      final product = _product!;
      final params = PurchaseParam(productDetails: product); // API genérica
      await _iap.buyNonConsumable(purchaseParam: params);

      // El resultado real llega por _onPurchaseUpdates
      return true;
    } catch (e) {
      dev.log('buyPro() error: $e');
      return false;
    }
  }

  Future<void> restore() async {
    try {
      await configureBilling();
      await _iap.restorePurchases();
    } catch (e) {
      dev.log('restore() error: $e');
    }
  }

  /// Cancela desde tu backend (si tienes endpoint para anular / marcar no-PRO).
  Future<bool> cancel() async {
    if (_loading) return false;

    _loading = true;
    _error = null;
    notifyListeners();

    try {
      final token = await session.getToken();
      if (token == null || token.isEmpty) {
        _status = 'not_authenticated';
        _isPremium = false;
        return false;
      }

      await api.cancel(token: token);
      await refresh(force: true);
      return true;
    } catch (e) {
      _error = e.toString();
      dev.log('subs.cancel() error: $_error');
      return false;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  // ========= Internos =========

  Future<void> _queryProduct() async {
    try {
      final resp = await _iap.queryProductDetails({_gpProductId});
      if (resp.error != null) {
        dev.log('queryProduct error: ${resp.error}');
      }
      if (resp.productDetails.isEmpty) {
        _product = null;
        dev.log('queryProduct: no se encontró $_gpProductId');
      } else {
        _product = resp.productDetails.first;
        dev.log('queryProduct OK: ${_product!.id}');
      }
    } catch (e) {
      dev.log('queryProduct exception: $e');
      _product = null;
    }
  }

  Future<void> _onPurchaseUpdates(List<PurchaseDetails> purchases) async {
    for (final p in purchases) {
      switch (p.status) {
        case PurchaseStatus.pending:
          dev.log('purchase pending...');
          break;

        case PurchaseStatus.purchased:
          // En prod: verifica recibo en backend antes de marcar PRO
          await _markPremium(true);
          await _complete(p);
          break;

        case PurchaseStatus.restored:
          await _markPremium(true);
          await _complete(p);
          break;

        case PurchaseStatus.error:
          dev.log('purchase error: ${p.error}');
          break;

        case PurchaseStatus.canceled:
          dev.log('purchase canceled by user');
          break;
      }
    }
    notifyListeners();
  }

  Future<void> _complete(PurchaseDetails purchase) async {
    if (purchase.pendingCompletePurchase) {
      await _iap.completePurchase(purchase); // acknowledge/finish
    }
  }

  Future<void> _markPremium(bool value) async {
    final changed = _isPremium != value;
    _isPremium = value;
    _status = value ? 'active' : 'none';
    if (changed) notifyListeners();
  }

  @override
  void dispose() {
    _purchaseSub?.cancel();
    super.dispose();
  }
}
