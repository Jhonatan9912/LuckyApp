// lib/presentation/screens/admin_dashboard/logic/referrals_controller.dart
import 'package:flutter/foundation.dart';

import 'package:base_app/data/api/admin_referrals_api.dart';
import 'package:base_app/data/models/referrals_summary.dart';
import 'package:base_app/data/models/top_referrer.dart';

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

  // -------------------------
  // Networking
  // -------------------------
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

  // -------------------------
  // Getters de conveniencia (UI)
  // -------------------------
  int get total => _summary?.total ?? 0;
  int get active => _summary?.active ?? 0;
  int get inactive => _summary?.inactive ?? 0;

  /// Comisiones en COP (valores enteros)
  int get pendingCop => _summary?.pendingCop ?? 0;
  int get paidCop => _summary?.paidCop ?? 0;

  /// Moneda (p.ej. "COP")
  String get currency => _summary?.currency ?? 'COP';

  // Labels numéricos para chips/KPIs
  String get totalLabel => total.toString();
  String get activeLabel => active.toString();
  String get inactiveLabel => inactive.toString();

  // Formateadores simples para mostrar en el cuadro de resumen
  // (no dependemos de intl; usamos puntos para miles estilo es_CO)
  String get pendingLabel => _fmtCop(pendingCop);
  String get paidLabel => _fmtCop(paidCop);

  // Alias para que el UI pueda llamar _ctrl.loadSummary();
  Future<void> loadSummary() => load();

  // -------------------------
  // Helpers
  // -------------------------
  String _fmtCop(int value) {
    // Convierte 15000 -> "$15.000"
    final s = value.abs().toString();
    final buf = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      final idxFromRight = s.length - i;
      buf.write(s[i]);
      final isThousandSepSpot = idxFromRight > 1 && (idxFromRight - 1) % 3 == 0;
      if (isThousandSepSpot) buf.write('.');
    }
    final sign = value < 0 ? '-' : '';
    return '$sign\$${buf.toString()}';
  }

  List<TopReferrer> _top = [];
  List<TopReferrer> get top => _top;

  Future<void> loadTop() async {
    debugPrint('[ReferralsController] loadTop() called');
    try {
      final items = await api.fetchTopReferrers();
      debugPrint('[ReferralsController] fetched top: len=${items.length}');
      _top = items;
    } catch (e, st) {
      debugPrint('[ReferralsController] loadTop ERROR: $e');
      debugPrint(st.toString()); // 👈 usa el stack trace
      _top = [];
    }

    notifyListeners();
  }
}
