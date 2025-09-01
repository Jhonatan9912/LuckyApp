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
  static const String _gpProductId = 'cm_suscripcion';
  ProductDetails? _product;

  // Evita refresh() superpuestos (causa clásica de parpadeo)
  bool _refreshing = false;
  Timer? _expiryTimer;

  // ========= Compat alias para no tocar tu app =========

  bool get isExpired =>
      _expiresAt != null && DateTime.now().isAfter(_expiresAt!);

  bool get isExpiringSoon =>
      _expiresAt != null &&
      _expiresAt!.difference(DateTime.now()) <= const Duration(minutes: 2);

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
  }

  void clear() {
    _expiryTimer?.cancel();
    _expiryTimer = null;
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

  void _armExpiryTimer() {
    _expiryTimer?.cancel();
    if (_expiresAt == null) return;

    final now = DateTime.now();
    final when = _expiresAt!;
    final delay = when.isAfter(now)
        ? when.difference(now) + const Duration(seconds: 2)
        : const Duration(seconds: 1);

    _expiryTimer = Timer(delay, () async {
      try {
        await refresh(force: true); // cuando vence, refresca con backend
      } catch (_) {}
    });
  }

Future<void> refresh({bool force = false}) async {
  if (_refreshing) return; // ← evita solapes

  // 👇 Salida rápida por TTL SIN tocar loading ni notifyListeners
  if (!force &&
      _lastFetch != null &&
      DateTime.now().difference(_lastFetch!) < ttl) {
    return;
  }

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

    // Intentar configurar billing
    try {
      if (!_billingConfigured) {
        await configureBilling();
      }
    } catch (e) {
      dev.log('subs.refresh() restore error: $e');
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

    _armExpiryTimer();

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

  Future<bool> buyPro() async {
    try {
      if (!_billingConfigured) {
        await configureBilling();
        if (!_billingConfigured) {
          throw Exception(
            'Google Play Billing no disponible en este dispositivo.',
          );
        }
      }

      if (_product == null) {
        await _queryProduct();
        if (_product == null) {
          throw Exception(
            'Producto $_gpProductId no encontrado en Play Console.',
          );
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
    _expiryTimer?.cancel();
    _purchaseSub?.cancel();
    super.dispose();
  }
}
