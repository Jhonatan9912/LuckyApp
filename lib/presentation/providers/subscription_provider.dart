import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show PlatformException; // 👈 para PlatformException
import 'package:base_app/data/api/subscriptions_api.dart';
import 'package:base_app/data/session/session_manager.dart';
import 'dart:developer' as dev;
import 'package:purchases_flutter/purchases_flutter.dart';

class SubscriptionProvider extends ChangeNotifier {
  final SubscriptionsApi api;
  final SessionManager session;
  final Duration ttl;

  SubscriptionProvider({
    required this.api,
    required this.session,
    this.ttl = const Duration(minutes: 5),
  });

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

  bool _rcConfigured = false;

  static const String _rcProductId = 'cm_suscripcion:monthly';

  // ========= PUBLIC =========

  Future<void> configureRC({
    required String apiKey,
    String? appUserId,
  }) async {
    if (_rcConfigured) return;

    final cfg = PurchasesConfiguration(apiKey);
    await Purchases.configure(cfg);
    _rcConfigured = true;

    if (appUserId != null && appUserId.isNotEmpty) {
      try {
        await Purchases.logIn(appUserId);
      } catch (e) {
        dev.log('RC logIn error: $e');
      }
    }

    try {
      await _refreshFromRC();
    } catch (_) {}
  }

  void clear() {
    _loading = false;
    _isPremium = false;
    _status = 'none';
    _expiresAt = null;
    _lastFetch = null;
    _error = null;
    _rcConfigured = false;
    notifyListeners();
  }

  Future<void> refresh({bool force = false}) async {
    _error = null;

    // 1) RC primero (no TTL)
    try {
      await _refreshFromRC();
    } catch (e) {
      dev.log('subs.refresh() RC error: $e');
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

      // Fusiona: si RC o backend dicen PRO, queda PRO
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
      if (!_rcConfigured) {
        throw Exception('RevenueCat no configurado. Llama configureRC() antes.');
      }

      final offerings = await Purchases.getOfferings();
      final current = offerings.current ?? offerings.all.values.firstOrNull;
      if (current == null) throw Exception('No hay offerings disponibles en RC');

      final pkg = current.availablePackages.firstWhere(
        (p) => p.storeProduct.identifier == _rcProductId,
        orElse: () => current.availablePackages.first,
      );

      final dynamic result = await Purchases.purchasePackage(pkg);

      final CustomerInfo info = _extractCustomerInfo(result);
      dev.log('RC purchase ok. Activos: ${info.entitlements.active.keys}');

      await _applyCustomerInfo(info);
      notifyListeners();
      return _isPremium;
    } on PlatformException catch (e) {
      final code = PurchasesErrorHelper.getErrorCode(e);
      dev.log('RC PlatformException: $code');
      return false;
    } catch (e) {
      dev.log('RC purchase error: $e');
      return false;
    }
  }

  Future<void> restore() async {
    if (!_rcConfigured) return;
    final info = await Purchases.restorePurchases();
    await _applyCustomerInfo(info);
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

  // ========= Internos RC =========

  Future<void> _refreshFromRC() async {
    if (!_rcConfigured) return;
    final info = await Purchases.getCustomerInfo();
    await _applyCustomerInfo(info);
  }

  CustomerInfo _extractCustomerInfo(dynamic result) {
    if (result is CustomerInfo) return result;
    try {
      final ci = (result as dynamic).customerInfo;
      if (ci is CustomerInfo) return ci;
    } catch (_) {}
    throw StateError('No se pudo extraer CustomerInfo del resultado de compra');
  }

  Future<void> _applyCustomerInfo(CustomerInfo info) async {
    final ent = info.entitlements.all['Pro'];
    final active = ent?.isActive ?? false;

    // expirationDate puede ser DateTime o String
    DateTime? exp;
    final Object? raw = ent?.expirationDate; 
    if (raw is DateTime) {
      exp = raw;
    } else if (raw is String) {
      exp = DateTime.tryParse(raw);
    } else {
      exp = null;
    }

    final changed = (_isPremium != active) ||
        (_expiresAt?.millisecondsSinceEpoch != exp?.millisecondsSinceEpoch);

    _isPremium = active;
    _status = active ? 'active' : 'none';
    _expiresAt = exp;

    if (changed) notifyListeners();

    dev.log('RC appUserId: ${info.originalAppUserId}');
    dev.log('RC entitlements activos: ${info.entitlements.active.keys}');
  }
}

// helper
extension _FirstOrNull<E> on Iterable<E> {
  E? get firstOrNull => isEmpty ? null : first;
}
