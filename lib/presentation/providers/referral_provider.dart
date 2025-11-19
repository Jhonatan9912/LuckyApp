import 'package:flutter/foundation.dart';
import 'package:base_app/data/api/referrals_api.dart';
import 'package:base_app/data/session/session_manager.dart';

class ReferralProvider extends ChangeNotifier {
  final ReferralsApi api;
  final SessionManager session;

  ReferralProvider({
    required this.api,
    required this.session,
  });

  bool _loading = false;
  bool get loading => _loading;

  // Contadores
  int total = 0;
  int activos = 0;
  int inactivos = 0;

  // Totales de comisión (resumen de payouts histórico)
  double comisionPendiente = 0.0; // pendiente por pagar (histórico)
  double comisionPagada = 0.0;    // ya pagada (histórico)
  String moneda = 'COP';

  // Montos operativos que usa la UI
  double availableCop = 0.0;      // Disponible para retiro (liberado)
  double pendingCop = 0.0;        // Retenida por 3 días (aún no disponible)
  double inWithdrawalCop = 0.0;   // En proceso de retiro
  double paidCop = 0.0;           // Total pagado (acumulado)
  double get heldCop => pendingCop;

  List<ReferralItem> items = [];

  /// Carga todo el estado visible (resumen + lista + totales de payouts)
  Future<void> load({bool refresh = false}) async {
    if (_loading) return;
    _loading = true;
    notifyListeners();

    try {
      // 0) VALIDAR TOKEN: si no hay sesión, no llamar al backend
      final token = await session.getToken();
      if (token == null || token.isEmpty) {
        if (kDebugMode) {
          debugPrint(
            '[referral_provider] No hay sesión → no cargar referidos',
          );
        }
        return; // el finally igual se ejecuta y apaga _loading
      }

      // 1) Resumen principal (fuente de verdad para saldos actuales)
      final summary = await api.fetchSummary();
      total = summary.total;
      activos = summary.activos;
      inactivos = summary.inactivos;

      // Valores fuertes desde el backend
      availableCop    = summary.availableCop;
      pendingCop      = summary.pendingCop;
      inWithdrawalCop = summary.inWithdrawalCop;
      paidCop         = summary.paidCop;
      moneda          = summary.currency ?? 'COP';

      if (kDebugMode) {
        debugPrint(
          '[referral_provider] summary '
          'avail=$availableCop held=$pendingCop '
          'in_withdrawal=$inWithdrawalCop paid=$paidCop currency=$moneda',
        );
      }

      // 2) Lista de referidos
      items = await api.fetchList(limit: 50, offset: 0);

      // 3) Totales de payouts (histórico). NO tocar available/pending aquí.
      try {
        final payouts = await api.fetchPayoutsSummary();
        comisionPendiente = payouts.pending;
        comisionPagada    = payouts.paid;

        // Si trae currency y está vacía la actual, úsala; si no, deja la del summary.
        if ((moneda.isEmpty || moneda == 'COP') &&
            (payouts.currency).isNotEmpty) {
          moneda = payouts.currency;
        }

        if (kDebugMode) {
          debugPrint(
            '[referral_provider] payouts '
            'pending(historic)=$comisionPendiente '
            'paid(historic)=$comisionPagada currency=$moneda',
          );
        }
      } catch (e) {
        if (kDebugMode) {
          debugPrint('[referral_provider] ERROR fetchPayoutsSummary: $e');
        }
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[referral_provider] ERROR load(): $e');
      }
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// Umbral mínimo de retiro: $100.000 COP.
  bool get canWithdraw => availableCop >= 100000.0;

  // Aliases usados por UI existente (si los necesitas)
  String get payoutCurrency => moneda;
  double get payoutPending => comisionPendiente;
  double get payoutPaid => comisionPagada;

  /// Crea una solicitud de retiro. NO mueve saldos en cliente.
  /// El backend debe:
  /// - Descontar atómicamente de `available` el monto enviado.
  /// - Aumentar `in_withdrawal` (en retiro) con ese monto.
  /// - Devolver el nuevo resumen para que `load()` lo refleje.
  Future<void> requestPayout({
    required double amountCop,
    required String accountType,              // 'bank' | 'nequi' | 'daviplata' | 'other'
    required Map<String, dynamic> payoutData, // número, titular, banco, etc.
  }) async {
    if (amountCop <= 0) {
      throw Exception('Monto inválido');
    }
    if (amountCop > availableCop) {
      throw Exception('El monto solicitado supera tu disponible');
    }
    if (!canWithdraw) {
      throw Exception('Aún no alcanzas \$100.000 para retirar');
    }

    _loading = true;
    notifyListeners();
    try {
      await api.createPayoutRequest(
        amountCop: amountCop,
        accountType: accountType,
        payoutData: payoutData,
      );

      // Recargar desde el backend para reflejar nuevos saldos
      await load(refresh: true);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[referral_provider] requestPayout ERROR: $e');
      }
      rethrow;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }
}
