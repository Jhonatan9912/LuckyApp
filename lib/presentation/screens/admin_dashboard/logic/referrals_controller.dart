// lib/presentation/screens/admin_dashboard/logic/referrals_controller.dart
import 'package:flutter/foundation.dart';

import 'package:base_app/data/api/admin_referrals_api.dart';
import 'package:base_app/data/models/referrals_summary.dart';

/// Controlador (ChangeNotifier) para manejar el estado del resumen de referidos.
///
/// Uso típico:
/// final ctrl = ReferralsController(api: AdminReferralsApi(baseUrl: kApiBase));
/// await ctrl.load();
/// AnimatedBuilder(animation: ctrl, builder: ...)
class ReferralsController extends ChangeNotifier {
  ReferralsController({required this.api});

  final AdminReferralsApi api;

  ReferralsSummary? _summary;
  ReferralsSummary? get summary => _summary;

  bool _loading = false;
  bool get loading => _loading;

  String? _error;
  String? get error => _error;

  /// Carga el resumen desde el backend.
  Future<void> load() async {
    if (_loading) return;
    _loading = true;
    _error = null;
    notifyListeners();

    try {
      final data = await api.fetchSummary();
      _summary = data;
    } catch (e) {
      _error = e.toString();
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// Limpia errores y datos (por ejemplo, al hacer pull-to-refresh antes de llamar a [load]).
  void reset() {
    _summary = null;
    _error = null;
    _loading = false;
    notifyListeners();
  }

  // Getters de conveniencia para el UI
  int get total => _summary?.total ?? 0;
  int get active => _summary?.active ?? 0;
  int get inactive => _summary?.inactive ?? 0;

  /// Texto listo para mostrar en chips o badges
  String get activeLabel => active.toString();
  String get inactiveLabel => inactive.toString();
  String get totalLabel => total.toString();
  /// Alias para que el UI pueda llamar _ctrl.loadSummary();
Future<void> loadSummary() => load();

}
