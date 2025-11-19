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
  DateTime? _since;
  DateTime? get since => _since;

  bool _autoRenewing = false;
  DateTime? get renewsAt => _autoRenewing ? _expiresAt : null;

  DateTime? _expiresAt;
  DateTime? get expiresAt => _expiresAt;

  DateTime? _lastFetch;
  String? _error;
  String? get error => _error;

  bool _activating = false;
  bool get activating => _activating;

 int? _maxDigits;
  int? get maxDigits => _maxDigits;
  // Usuario al que pertenece el estado de esta instancia del provider
  int? _ownerUserId;

  /// Getter para usar en Paywall
  ProductDetails? get product => _product;
  String? get priceString => _product?.price;

  // ========= Internos Billing =========
  final InAppPurchase _iap = InAppPurchase.instance;
  bool _billingConfigured = false;
  StreamSubscription<List<PurchaseDetails>>? _purchaseSub;

  // ⚠️ AJUSTA ESTO al productId EXACTO en Play Console (NO base plan)
  static const Set<String> _gpProductIds = {
    'cm_suscripcion',
    'cml_suscripcion',
  };
  ProductDetails? _product;
  // NUEVO: lista completa de productos consultados
  List<ProductDetails> _products = [];

  // Getters de compat + múltiples
  List<ProductDetails> get products => _products;
  ProductDetails? productById(String id) {
    final i = _products.indexWhere((p) => p.id == id);
    if (i >= 0) return _products[i];
    return _product ?? (_products.isNotEmpty ? _products.first : null);
  }

  String? priceStringFor(String id) => productById(id)?.price;

  // Evita refresh() superpuestos (causa clásica de parpadeo)
  bool _refreshing = false;

  // ========= Compat alias para no tocar tu app =========
  Future<void> configureRC({required String apiKey, String? appUserId}) async {
    await configureBilling();
  }

  /// Nueva forma explícita
  Future<void> configureBilling() async {
    if (_billingConfigured) return;

    final available = await _iap.isAvailable();
    if (!available) {
      dev.log(
        'Billing no disponible (¿Play Store instalada / app desde Play? )',
      );
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

  void _reset() {
    _loading = false;
    _isPremium = false;
    _status = 'none';
    _since = null;
    _expiresAt = null;
    _autoRenewing = false;
    _lastFetch = null;
    _error = null;
    _maxDigits = null;
  }

  void clear() {
    _reset();
    _ownerUserId = null;
    _purchaseSub?.cancel();
    _purchaseSub = null;
    _billingConfigured = false;
    notifyListeners();
  }

  // Parse seguro de ISO8601 a DateTime local
  DateTime? _parseDate(dynamic v) {
    if (v == null) return null;
    try {
      return DateTime.parse(v.toString()).toLocal();
    } catch (_) {
      return null;
    }
  }

  Future<void> refresh({bool force = false}) async {
    if (_refreshing) return; // ← evita solapes
    _refreshing = true;
    _loading = true;
    _error = null;
    notifyListeners();

    try {
      // Detectar usuario actual
      final uidDyn = await session.getUserId();
      final uid = uidDyn is int ? uidDyn : int.tryParse('$uidDyn');

      // Si cambió el usuario, resetea el estado a FREE
      if (_ownerUserId != uid) {
        _ownerUserId = uid;
        _reset();
        _loading = true; // volvemos a marcar loading después del reset
        notifyListeners();
      }

      // Intentar configurar billing (no cambia el estado premium por sí solo)
      try {
        if (!_billingConfigured) {
          await configureBilling();
        }
        // No hagas restorePurchases() aquí; hazlo bajo demanda (botón Restaurar).
      } catch (e) {
        dev.log('subs.refresh() restore error: $e');
      }

      // TTL por usuario
      if (!force &&
          _lastFetch != null &&
          DateTime.now().difference(_lastFetch!) < ttl) {
        return;
      }

      final token = await session.getToken();
      if (token == null || token.isEmpty || uid == null) {
        _reset();
        _status = 'not_authenticated';
        _lastFetch = DateTime.now();
        return; // el finally apaga loading/refreshing
      }

      final json = await api.getStatus(token: token);
      dev.log('subs.refresh() status payload: $json');

      final backendIsPremium = (json['isPremium'] == true);
      final backendStatus = (json['status'] ?? 'none').toString();

      _isPremium = backendIsPremium;
      _status = backendIsPremium ? 'active' : backendStatus;

      _since = _parseDate(json['since']); // e.g. "2025-08-15T12:00:00Z"
      _expiresAt = _parseDate(json['expiresAt']); // e.g. "2025-09-15T12:00:00Z"
      _autoRenewing =
          (json['autoRenewing'] == true) || (json['auto_renewing'] == true);

      // 👇 NUEVO: leer maxDigits desde backend
      final rawMaxDigits = json['maxDigits'] ?? json['max_digits'];

      if (rawMaxDigits is int) {
        _maxDigits = rawMaxDigits;
      } else if (rawMaxDigits is String) {
        _maxDigits = int.tryParse(rawMaxDigits);
      } else {
        // Fallback: si es premium pero backend no manda nada, asumimos 3
        _maxDigits = _isPremium ? 3 : null;
      }

      // Guarda cache local (por si UI lo necesita muy pronto)
      await session.setIsPremium(_isPremium);

      _lastFetch = DateTime.now();

    } catch (e) {
      _error = e.toString();
      dev.log('subs.refresh() backend error: $_error');
      // No forzamos _reset() para no “brincar” de PRO a FREE ante un glitch.
    } finally {
      _loading = false;
      _refreshing = false; // ← libera el candado
      notifyListeners();
    }
  }

  Future<bool> buyPro({String? productId}) async {
    try {
      if (!_billingConfigured) {
        await configureBilling();
        if (!_billingConfigured) {
          throw Exception(
            'Google Play Billing no disponible en este dispositivo.',
          );
        }
      }

      if (_products.isEmpty) {
        await _queryProduct();
        if (_products.isEmpty) {
          throw Exception(
            'Productos no encontrados en Play Console: $_gpProductIds',
          );
        }
      }

      // Si no te pasan productId, usa el primero (compatibilidad)
      final ProductDetails? product =
          (productId != null ? productById(productId) : _product) ??
          (_products.isNotEmpty ? _products.first : null);

      if (product == null) {
        throw Exception('Producto no disponible.');
      }

      final params = PurchaseParam(productDetails: product);
      await _iap.buyNonConsumable(purchaseParam: params);

      return true; // el resultado final llega por _onPurchaseUpdates
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
      final resp = await _iap.queryProductDetails(_gpProductIds);
      if (resp.error != null) {
        dev.log('queryProduct error: ${resp.error}');
      }
      _products = resp.productDetails;

      if (_products.isEmpty) {
        _product = null;
        dev.log('queryProduct: no se encontraron $_gpProductIds');
      } else {
        // Mantén compatibilidad: el “producto por defecto” será el primero
        _product = _products.first;
        dev.log('queryProduct OK: ${_products.map((p) => p.id).toList()}');
      }
    } catch (e) {
      dev.log('queryProduct exception: $e');
      _products = [];
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
        case PurchaseStatus.restored:
          try {
            _activating = true;
            notifyListeners();

            final token = await session.getToken();
            await api.syncPurchase(
              token: token ?? '',
              productId: p.productID,
              purchaseId: p.purchaseID ?? '',
              verificationData: p.verificationData.serverVerificationData,
            );
          } catch (e) {
            dev.log('syncPurchase error: $e');
          } finally {
            await _complete(p);
            // Breve espera por propagación en backend (ajústalo si quieres)
            await Future.delayed(const Duration(seconds: 1));
            await refresh(force: true);
            _activating = false;
            notifyListeners();
          }
          break;

        case PurchaseStatus.error:
          dev.log('purchase error: ${p.error}');
          break;

        case PurchaseStatus.canceled:
          dev.log('purchase canceled by user');
          break;
      }
    }
  }

  Future<void> _complete(PurchaseDetails purchase) async {
    if (purchase.pendingCompletePurchase) {
      await _iap.completePurchase(purchase); // acknowledge/finish
    }
  }

  @override
  void dispose() {
    _purchaseSub?.cancel();
    super.dispose();
  }
}
