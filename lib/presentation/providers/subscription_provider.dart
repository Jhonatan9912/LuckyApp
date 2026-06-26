import 'dart:async';
import 'dart:developer' as dev;

import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import 'package:base_app/data/api/subscriptions_api.dart';
import 'package:base_app/data/session/session_manager.dart';

// 👇 NUEVO: modos escalables (3,4,quinta)
import 'package:base_app/presentation/screens/dashboard/logic/game_mode.dart';

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

  // ==========================================================
  // ✅ NUEVO: Modo(s) permitidos (esto reemplaza maxDigits)
  // ==========================================================
  Set<GameMode> _allowedModes = <GameMode>{};
  Set<GameMode> get allowedModes => Set.unmodifiable(_allowedModes);

  bool canUse(GameMode mode) => _allowedModes.contains(mode);

  /// Máximo de dígitos desbloqueados por el plan activo.
  /// null = sin suscripción (solo preview)
  /// 2 = plan starter (10k) — solo 2 cifras
  /// 3 = plan lite (20k) — 2 y 3 cifras
  /// 4 = plan full (60k) — 2, 3 y 4 cifras
  /// 5 = plan ultra (100k) — 2, 3, 4 y 5 cifras
  int? get maxDigits {
    if (!_isPremium) return null;
    if (_allowedModes.contains(GameMode.quinta)) return 5;
    if (_allowedModes.contains(GameMode.digits4)) return 4;
    if (_allowedModes.contains(GameMode.digits3)) return 3;
    if (_allowedModes.contains(GameMode.digits2)) return 2;
    return null;
  }

  // Usuario al que pertenece el estado de esta instancia del provider
  int? _ownerUserId;

  /// Getter para usar en Paywall
  ProductDetails? get product => _product;
  String? get priceString => _product?.price;

  // ========= Internos Billing =========
  final InAppPurchase _iap = InAppPurchase.instance;
  bool _billingConfigured = false;
  StreamSubscription<List<PurchaseDetails>>? _purchaseSub;

  static const Set<String> _gpProductIds = {
    'cms_suscripcion',
    'cml_suscripcion',
    'cm_suscripcion',
    'cmu_suscripcion',
  };

  ProductDetails? _product;
  List<ProductDetails> _products = [];

  // Getters de compat + múltiples
  List<ProductDetails> get products => _products;
  ProductDetails? productById(String id) {
    final i = _products.indexWhere((p) => p.id == id);
    if (i >= 0) return _products[i];
    return _product ?? (_products.isNotEmpty ? _products.first : null);
  }

  String? priceStringFor(String id) => productById(id)?.price;

  // Evita refresh() superpuestos
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
      dev.log('Billing no disponible (¿Play Store instalada / app desde Play? )');
      _billingConfigured = false;
      return;
    }

    _purchaseSub ??= _iap.purchaseStream.listen(
      _onPurchaseUpdates,
      onError: (e) => dev.log('purchaseStream error: $e'),
      onDone: () => dev.log('purchaseStream done'),
    );

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

    // 👇 NUEVO
    _allowedModes = <GameMode>{};
  }

  void clear() {
    _reset();
    _ownerUserId = null;
    _purchaseSub?.cancel();
    _purchaseSub = null;
    _billingConfigured = false;
    notifyListeners();
  }

  DateTime? _parseDate(dynamic v) {
    if (v == null) return null;
    try {
      return DateTime.parse(v.toString()).toLocal();
    } catch (_) {
      return null;
    }
  }

  // ==========================================================
  // ✅ Normalizador: backend -> allowedModes
  // ==========================================================
  Set<GameMode> _modesFromBackend(Map<String, dynamic> json, bool isPremium) {
    final base = <GameMode>{};

    if (!isPremium) return base;

    // 1) Soporte futuro: backend envía allowedModes / allowed_modes como lista
    final rawAllowed = json['allowedModes'] ?? json['allowed_modes'];
    if (rawAllowed is List) {
      final set = <GameMode>{...base};
      for (final v in rawAllowed) {
        final s = v.toString().trim().toLowerCase();
        if (s == '2' || s == 'digits2' || s == '2digits') set.add(GameMode.digits2);
        if (s == '3' || s == 'digits3' || s == '3digits') set.add(GameMode.digits3);
        if (s == '4' || s == 'digits4' || s == '4digits') set.add(GameMode.digits4);
        if (s == 'quinta' || s == '5' || s == 'fifth') set.add(GameMode.quinta);
      }
      if (set.length > 1) return set;
    }

    // 2) Compat actual: backend manda maxDigits/max_digits
    final rawMaxDigits = json['maxDigits'] ?? json['max_digits'];
    int? md;
    if (rawMaxDigits is int) {
      md = rawMaxDigits;
    } else if (rawMaxDigits is String) {
      md = int.tryParse(rawMaxDigits);
    }

    // md=2 → solo 2 cifras (plan starter 10k)
    // md=3 → 2 + 3 cifras
    // md=4 → 2, 3 y 4 cifras
    // md=5 → 2, 3, 4 y quinta
    if (md == 2) return <GameMode>{GameMode.digits2};
    if (md == 3) return <GameMode>{GameMode.digits2, GameMode.digits3};
    if (md == 4) return <GameMode>{GameMode.digits2, GameMode.digits3, GameMode.digits4};
    if (md == 5) return <GameMode>{GameMode.digits2, GameMode.digits3, GameMode.digits4, GameMode.quinta};

    // Fallback: premium pero sin info -> mínimo 2+3 cifras
    return <GameMode>{GameMode.digits2, GameMode.digits3};
  }

  Future<void> refresh({bool force = false}) async {
    if (_refreshing) return;
    _refreshing = true;

    _loading = true;
    _error = null;
    notifyListeners();

    try {
      final uidDyn = await session.getUserId();
      final uid = uidDyn is int ? uidDyn : int.tryParse('$uidDyn');

      if (_ownerUserId != uid) {
        _ownerUserId = uid;
        _reset();
        _loading = true;
        notifyListeners();
      }

      try {
        if (!_billingConfigured) {
          await configureBilling();
        }
      } catch (e) {
        dev.log('subs.refresh() billing error: $e');
      }

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
        return;
      }

      final json = await api.getStatus(token: token);
      dev.log('subs.refresh() status payload: $json');

      final backendIsPremium = (json['isPremium'] == true);
      final backendStatus = (json['status'] ?? 'none').toString();

      _isPremium = backendIsPremium;
      _status = backendIsPremium ? 'active' : backendStatus;

      _since = _parseDate(json['since']);
      _expiresAt = _parseDate(json['expiresAt']);
      _autoRenewing =
          (json['autoRenewing'] == true) || (json['auto_renewing'] == true);

      // 👇 NUEVO: aquí se decide todo lo “jugable”
      _allowedModes = _modesFromBackend(
        (json is Map<String, dynamic>) ? json : <String, dynamic>{},
        _isPremium,
      );

      await session.setIsPremium(_isPremium);
      _lastFetch = DateTime.now();
    } catch (e) {
      _error = e.toString();
      dev.log('subs.refresh() backend error: $_error');
    } finally {
      _loading = false;
      _refreshing = false;
      notifyListeners();
    }
  }

  Future<bool> buyPro({String? productId}) async {
    try {
      if (!_billingConfigured) {
        await configureBilling();
        if (!_billingConfigured) {
          throw Exception('Google Play Billing no disponible en este dispositivo.');
        }
      }

      if (_products.isEmpty) {
        await _queryProduct();
        if (_products.isEmpty) {
          throw Exception('Productos no encontrados en Play Console: $_gpProductIds');
        }
      }

      final ProductDetails? product =
          (productId != null ? productById(productId) : _product) ??
              (_products.isNotEmpty ? _products.first : null);

      if (product == null) {
        throw Exception('Producto no disponible.');
      }

      final params = PurchaseParam(productDetails: product);
      await _iap.buyNonConsumable(purchaseParam: params);
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
        _allowedModes = <GameMode>{};
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
      await _iap.completePurchase(purchase);
    }
  }

  @override
  void dispose() {
    _purchaseSub?.cancel();
    super.dispose();
  }
}
