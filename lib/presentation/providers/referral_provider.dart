import 'package:flutter/foundation.dart';
import 'package:base_app/data/api/referrals_api.dart';

class ReferralProvider extends ChangeNotifier {
  final ReferralsApi api;
  ReferralProvider({required this.api});

  bool _loading = false;
  bool get loading => _loading;

  int total = 0;
  int activos = 0;
  int inactivos = 0;

  // Totales de comisión
  double comisionPendiente = 0.0;
  double comisionPagada = 0.0;
  String moneda = 'COP';

  List<ReferralItem> items = [];

  Future<void> load({bool refresh = false}) async {
    if (_loading) return;
    _loading = true;
    notifyListeners();

    try {
      // 1) Resumen (conteos)
      final summary = await api.fetchSummary();
      total = summary.total;
      activos = summary.activos;
      inactivos = summary.inactivos;

      // 2) Lista de referidos
      items = await api.fetchList(limit: 50, offset: 0);

      // 3) Totales de comisiones
      try {
        final payouts = await api.fetchPayoutsSummary();
        comisionPendiente = payouts.pending;
        comisionPagada = payouts.paid;
        moneda = payouts.currency; // <-- IMPORTANTE: guardar la moneda

        debugPrint(
          '[referral_provider] pending=$comisionPendiente paid=$comisionPagada currency=$moneda',
        );
      } catch (e) {
        debugPrint('[referral_provider] ERROR payouts: $e');
        comisionPendiente = 0.0;
        comisionPagada = 0.0;
        // moneda la dejamos como esté
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error cargando referidos: $e');
      }
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  bool get canWithdraw => comisionPendiente > 0.0;

  // Aliases usados por la UI
  String get payoutCurrency => moneda;
  double get payoutPending => comisionPendiente;
  double get payoutPaid => comisionPagada;
}
