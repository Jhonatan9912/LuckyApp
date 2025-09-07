import 'package:flutter/foundation.dart';

import 'package:base_app/domain/models/bank.dart';
import 'package:base_app/domain/models/payout_request.dart';
import 'package:base_app/data/api/payouts_api.dart';

class PayoutsProvider extends ChangeNotifier {
  final PayoutsApi api;

  PayoutsProvider({required this.api});

  // Estados
  bool loadingBanks = false;
  bool submitting = false;

  // ⚠️ Errores separados para no mezclar mensajes en la UI
  String? banksError;   // errores al cargar bancos
  String? submitError;  // errores al enviar la solicitud

  List<Bank> _banks = [];
  List<Bank> get banks => _banks;

  /// Limpia errores manualmente (por si el caller lo necesita)
  void clearErrors() {
    banksError = null;
    submitError = null;
    notifyListeners();
  }

  Future<void> loadBanks({bool force = false}) async {
    if (!force && _banks.isNotEmpty) return;
    loadingBanks = true;
    banksError = null; // solo tocamos el error de bancos
    notifyListeners();

    try {
      _banks = await api.fetchBanks(onlyActive: true);
    } catch (e) {
      banksError = e.toString();
      _banks = [];
    } finally {
      loadingBanks = false;
      notifyListeners();
    }
  }

  /// Bancos filtrados por tipo (ej: 'BANK', 'CF', 'SEDPE')
  List<Bank> banksByType(String type) =>
      _banks.where((b) => b.entityType.toUpperCase() == type.toUpperCase()).toList();

  Future<bool> submit(PayoutRequestInput input) async {
    submitting = true;
    submitError = null; // solo tocamos el error de submit
    notifyListeners();

    try {
      final ok = await api.submitPayoutRequest(input);
      return ok;
    } catch (e) {
      submitError = e.toString();
      return false;
    } finally {
      submitting = false;
      notifyListeners();
    }
  }
}
