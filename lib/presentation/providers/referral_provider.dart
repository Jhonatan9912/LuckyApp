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

  // Totales de comisión (payouts endpoint)
  double comisionPendiente = 0.0;
  double comisionPagada = 0.0;
  String moneda = 'COP';

  // NUEVO: montos que la vista usa directamente
  double availableCop = 0.0; // “Comisión disponible” que quieres mostrar
  double pendingCop = 0.0;
  double paidCop = 0.0;
  double get heldCop => pendingCop;
  
  List<ReferralItem> items = [];

  Future<void> load({bool refresh = false}) async {
    if (_loading) return;
    _loading = true;
    notifyListeners();

    try {
      final summary = await api.fetchSummary();
      total = summary.total;
      activos = summary.activos;
      inactivos = summary.inactivos;

      // ← clave
      availableCop = summary.availableCop;
      pendingCop = summary.pendingCop;
      paidCop = summary.paidCop;

      debugPrint(
        '[provider] summary avail=$availableCop pend=$pendingCop paid=$paidCop',
      );

      // Si tu ReferralSummary YA incluye montos del backend (available_cop, pending_cop, paid_cop),
      // los tomamos aquí. Si no, este bloque se salta sin romper.
      try {
        final dyn = summary as dynamic;
        final a = dyn.availableCop;
        final p = dyn.pendingCop;
        final d = dyn.paidCop;
        if (a is num) availableCop = a.toDouble();
        if (p is num) pendingCop = p.toDouble();
        if (d is num) paidCop = d.toDouble();
      } catch (_) {
        // summary no trae montos; seguimos con fallback de payouts
      }

      // 2) Lista de referidos
      items = await api.fetchList(limit: 50, offset: 0);

      // 3) Totales de comisiones (payouts)
      try {
        final payouts = await api.fetchPayoutsSummary();
        comisionPendiente = payouts.pending;
        comisionPagada = payouts.paid;
        moneda = payouts.currency;

        // Fallback: si summary no trajo availableCop (>0) usa el pending de payouts
        if (availableCop <= 0.0 && comisionPendiente > 0.0) {
          availableCop = comisionPendiente;
        }

        if (kDebugMode) {
          debugPrint(
            '[referral_provider] availableCop=$availableCop pending=$comisionPendiente paid=$comisionPagada currency=$moneda',
          );
        }
      } catch (e) {
        debugPrint('[referral_provider] ERROR payouts: $e');
        // No tocamos availableCop aquí; si vino en summary, se mantiene.
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Error cargando referidos: $e');
      }
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  bool get canWithdraw => availableCop > 0.0 || comisionPendiente > 0.0;

  // Aliases usados por la UI existente
  String get payoutCurrency => moneda;
  double get payoutPending => comisionPendiente;
  double get payoutPaid => comisionPagada;
}
