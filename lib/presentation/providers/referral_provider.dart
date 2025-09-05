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
  double inWithdrawalCop = 0.0; // NUEVO: “En retiro / En proceso”

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

      // Lee “En retiro” si ya viene en el summary
      try {
        final dyn = summary as dynamic;

        // casos camelCase (si tu ReferralsApi mapea llaves)
        final iw1 = (dyn.inWithdrawalCop as num?);

        // fallback a snake_case directo (si summary es un Map/dto plano)
        final iw2 = (dyn.in_withdrawal_cop as num?);

        if (iw1 != null) {
          inWithdrawalCop = iw1.toDouble();
        } else if (iw2 != null) {
          inWithdrawalCop = iw2.toDouble();
        }
      } catch (_) {
        // Si no viene en el summary, lo dejamos en 0.0
        inWithdrawalCop = 0.0;
      }

      debugPrint(
        '[provider] summary avail=$availableCop held=$pendingCop in_withdrawal=$inWithdrawalCop paid=$paidCop',
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
            '[referral_provider] (payouts) fallback avail=$availableCop held=$pendingCop in_withdrawal=$inWithdrawalCop paid=$paidCop currency=$moneda',
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

  bool get canWithdraw => availableCop >= 100000.0;

  // Aliases usados por la UI existente
  String get payoutCurrency => moneda;
  double get payoutPending => comisionPendiente;
  double get payoutPaid => comisionPagada;
}
