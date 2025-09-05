import 'package:flutter/foundation.dart';

import 'package:base_app/domain/models/bank.dart';
import 'package:base_app/domain/models/payout_request.dart';
import 'package:base_app/data/api/payouts_api.dart';

class PayoutsProvider extends ChangeNotifier {
  final PayoutsApi api;

  PayoutsProvider({required this.api});

  bool loadingBanks = false;
  bool submitting = false;
  String? error;
  List<Bank> _banks = [];

  List<Bank> get banks => _banks;

  Future<void> loadBanks({bool force = false}) async {
    if (!force && _banks.isNotEmpty) return;
    loadingBanks = true;
    error = null;
    notifyListeners();
    try {
      _banks = await api.fetchBanks(onlyActive: true);
    } catch (e) {
      error = e.toString();
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
    error = null;
    notifyListeners();  
    try {
      final ok = await api.submitPayoutRequest(input);
      return ok;
    } catch (e) {
      error = e.toString();
      return false;
    } finally {
      submitting = false;
      notifyListeners();
    }
  }
}
