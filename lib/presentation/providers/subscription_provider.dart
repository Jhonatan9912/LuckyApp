import 'package:flutter/foundation.dart';
import 'package:base_app/data/api/subscriptions_api.dart';
import 'package:base_app/data/session/session_manager.dart';
import 'dart:developer' as dev;

/// Mantiene en memoria el estado de la suscripción del usuario.
/// - Fuente: backend (/api/subscriptions/status)
/// - Con caché simple (TTL) para evitar spamear la API.
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

  /// Limpia el estado (úsalo al cerrar sesión).
  void clear() {
    _loading = false;
    _isPremium = false;
    _status = 'none';
    _expiresAt = null;
    _lastFetch = null;
    _error = null;
    notifyListeners();
  }

  /// Refresca desde backend respetando TTL (usa `force: true` para saltarlo).
  Future<void> refresh({bool force = false}) async {
    if (!force &&
        _lastFetch != null &&
        DateTime.now().difference(_lastFetch!) < ttl) {
      return; // cache válida
    }

    _loading = true;
    _error = null;
    notifyListeners();

    try {
      final token = await session.getToken();
      dev.log('subs.refresh() token presente? ${token != null && token.isNotEmpty}');

      if (token == null || token.isEmpty) {
        _isPremium = false;
        _status = 'not_authenticated';
        _expiresAt = null;
        _lastFetch = DateTime.now();
        _loading = false;
        notifyListeners();
        return;
      }

      final json = await api.getStatus(token: token);
      dev.log('subs.refresh() status payload: $json');

      _isPremium = (json['isPremium'] == true);
      _status = (json['status'] ?? 'none').toString();

      final exp = json['expiresAt'] as String?;
      _expiresAt = exp != null ? DateTime.tryParse(exp) : null;

      _lastFetch = DateTime.now();
      dev.log('subs.refresh() result -> isPremium=$_isPremium, status=$_status, expiresAt=$_expiresAt');
    } catch (e) {
      _error = e.toString();
      dev.log('subs.refresh() error: $_error');
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// Cancela la suscripción actual en backend.
  /// Retorna true si se canceló correctamente, false si falló.
  Future<bool> cancel() async {
    if (_loading) return false; // evita doble toque mientras hay otra operación

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

      // 👉 usamos tu API ya inyectada
      await api.cancel(token: token);

      // refresca el estado desde el backend (sin TTL)
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
}
