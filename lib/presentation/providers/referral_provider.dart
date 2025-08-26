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

  double comisionPendiente = 0.0;
  double comisionPagada = 0.0;

  List<ReferralItem> items = [];

  Future<void> load({bool refresh = false}) async {
    if (_loading) return;
    _loading = true;
    notifyListeners();

    try {
      // 1) Resumen (total / activos / inactivos)
      final summary = await api.fetchSummary();
      total = summary.total;
      activos = summary.activos;
      inactivos = summary.inactivos;

      // 2) Lista de referidos
      items = await api.fetchList(limit: 50, offset: 0);

      // 3) Resumen de comisiones (pendiente / pagada)
      try {
        final payouts = await api.fetchPayoutsSummary();
        comisionPendiente = payouts.pending;
        comisionPagada = payouts.paid;
      } catch (e) {
        // Si falla el endpoint de payouts, no rompas la carga
        if (kDebugMode) {
          print('Error obteniendo payouts summary: $e');
        }
        comisionPendiente = 0.0;
        comisionPagada = 0.0;
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

  /// Mostrar el botón "Solicitar retiro" sólo si hay algo pendiente (> 0).
  /// Si manejas un mínimo, cambia a: `comisionPendiente >= 20000`.
  bool get canWithdraw => comisionPendiente > 0.0;
}
