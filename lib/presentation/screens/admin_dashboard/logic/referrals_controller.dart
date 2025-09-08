// lib/presentation/screens/admin_dashboard/logic/referrals_controller.dart
import 'package:flutter/foundation.dart';

import 'package:base_app/data/api/admin_referrals_api.dart';
import 'package:base_app/data/models/referrals_summary.dart';
import 'package:base_app/data/models/top_referrer.dart';
import 'package:base_app/domain/models/commission_request.dart';
import 'package:base_app/data/models/admin_user_detail.dart';
import 'package:base_app/data/models/commission_breakdown.dart';
import 'dart:io';
import 'package:base_app/data/models/payout_batch.dart';
import 'package:base_app/data/models/payout_batch_detail.dart';

/// Controlador para resumen de referidos, top, comisiones,
/// detalle de usuario y desglose por solicitud.
class ReferralsController extends ChangeNotifier {
  ReferralsController({required this.api});

  final AdminReferralsApi api;

  // ===== Resumen =====
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

  /// Limpia errores y datos.
  void reset() {
    _summary = null;
    _error = null;
    _loading = false;
    notifyListeners();
  }

  // Getters convenientes para UI
  int get total => _summary?.total ?? 0;
  int get active => _summary?.active ?? 0;
  int get inactive => _summary?.inactive ?? 0;

  int get pendingCop => _pendingCopFromCommissions ?? _summary?.pendingCop ?? 0;
  int get paidCop => _paidCopFromPayouts ?? _summary?.paidCop ?? 0;

  String get currency => _summary?.currency ?? 'COP';

  String get totalLabel => total.toString();
  String get activeLabel => active.toString();
  String get inactiveLabel => inactive.toString();

  String get pendingLabel => _fmtCop(pendingCop);
  String get paidLabel => _fmtCop(paidCop);

  Future<void> loadSummary() => load();

  String _fmtCop(int value) {
    // 15000 -> "$15.000"
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

  // ===== Top referidos =====
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
      debugPrint(st.toString());
      _top = [];
    }
    notifyListeners();
  }

  // ===== Comisiones (solicitudes) =====

  String get pendingCommissionsLabel => pendingCommissionsCount.toString();
  bool _loadingCommissions = false;
  String? _commissionsError;
  List<CommissionRequest> _commissions = [];
  int? _pendingCopFromCommissions; // total pendiente calculado desde la lista
  bool get loadingCommissions => _loadingCommissions;
  String? get commissionsError => _commissionsError;
  List<CommissionRequest> get commissions => _commissions;
  int get pendingCommissionsCount => _commissions.length;

  Future<void> loadCommissions({String? status}) async {
    _loadingCommissions = true;
    _commissionsError = null;
    notifyListeners();
    try {
      _commissions = await api.fetchCommissionRequests(status: status);
      // Si estamos viendo las pendientes, recalculamos el KPI "Pendiente"
      if (status == null || status == 'requested' || status == 'pending') {
        final total = _commissions
            .where((c) {
              final s = c.status.toLowerCase();
              return s == 'requested' || s == 'pending';
            })
            .fold<double>(0.0, (sum, c) => sum + (c.amountCop));
        _pendingCopFromCommissions = total.round();
      } else {
        // En otros filtros no sobreescribimos: usamos el summary del backend
        _pendingCopFromCommissions = null;
      }
    } catch (e) {
      _commissionsError = e.toString();
      _commissions = [];
    } finally {
      _loadingCommissions = false;
      notifyListeners();
    }
  }

  // ===== Pagos (lotes ya hechos) =====
  bool _loadingPayouts = false;
  String? _payoutsError;
  List<PayoutBatch> _payouts = [];
  int? _paidCopFromPayouts; // total pagado calculado desde los lotes de pago

  bool get loadingPayouts => _loadingPayouts;
  String? get payoutsError => _payoutsError;
  List<PayoutBatch> get payouts => _payouts;

  Future<void> loadPayouts() async {
    _loadingPayouts = true;
    _payoutsError = null;
    notifyListeners();
    try {
      _payouts = await api.fetchPayoutBatches();
      // ➜ Total pagado hasta hoy (inclusive) desde la lista de pagos
      final now = DateTime.now();
      bool isSameDay(DateTime a, DateTime b) =>
          a.year == b.year && a.month == b.month && a.day == b.day;

      int parseCopLabel(String s) {
        final digits = s.replaceAll(RegExp(r'[^\d]'), '');
        return int.tryParse(digits) ?? 0;
      }

      // Suma usando createdAt <= hoy y el total del lote
      int sum = 0;
      for (final b in _payouts) {
        final dt = b.createdAt; // puede ser null
        if (dt == null) continue;
        final isBeforeToday = dt.isBefore(
          DateTime(now.year, now.month, now.day, 23, 59, 59),
        );
        final isToday = isSameDay(dt, now);
        if (isBeforeToday || isToday) {
          // Si tu modelo tiene un numérico (p. ej. b.totalCop o b.totalCopValue), úsalo.
          // final amount = (b.totalCop ?? b.totalCopValue ?? 0);
          // Si no, parsea la etiqueta (ya la usas en el UI):
          final amount = parseCopLabel(b.totalCopLabel);
          sum += amount;
        }
      }
      _paidCopFromPayouts = sum;
    } catch (e) {
      _payoutsError = e.toString();
      _payouts = [];
    } finally {
      _loadingPayouts = false;
      notifyListeners();
    }
  }

  // === Estado de pago en progreso ===
  // ===== Detalle de lote de pago =====
  PayoutBatchDetails? _currentBatchDetails;
  bool _loadingBatchDetails = false;
  String? _batchDetailsError;

  PayoutBatchDetails? get currentBatchDetails => _currentBatchDetails;
  bool get loadingBatchDetails => _loadingBatchDetails;
  String? get batchDetailsError => _batchDetailsError;

  bool _paying = false;
  bool get paying => _paying;

  // ===== Detalle de usuario (Ver usuario) =====
  final Map<int, AdminUserDetail> _userDetailCache = {};
  AdminUserDetail? _currentUserDetail;
  bool _loadingUserDetail = false;
  String? _userDetailError;

  AdminUserDetail? get currentUserDetail => _currentUserDetail;
  bool get loadingUserDetail => _loadingUserDetail;
  String? get userDetailError => _userDetailError;

  void clearUserDetail() {
    _currentUserDetail = null;
    _userDetailError = null;
    _loadingUserDetail = false;
    notifyListeners();
  }

  Future<AdminUserDetail?> loadUserDetail(
    int userId, {
    bool force = false,
  }) async {
    if (!force && _userDetailCache.containsKey(userId)) {
      _currentUserDetail = _userDetailCache[userId];
      _userDetailError = null;
      _loadingUserDetail = false;
      notifyListeners();
      return _currentUserDetail;
    }

    _loadingUserDetail = true;
    _userDetailError = null;
    _currentUserDetail = null;
    notifyListeners();

    try {
      final detail = await api.fetchUserDetail(userId);
      _userDetailCache[userId] = detail;
      _currentUserDetail = detail;
      return detail;
    } catch (e, st) {
      debugPrint('loadUserDetail ERROR: $e\n$st');
      _userDetailError = e.toString();
      _currentUserDetail = null;
      return null;
    } finally {
      _loadingUserDetail = false;
      notifyListeners();
    }
  }

  // === Estado de rechazo en progreso ===
  bool _rejecting = false;
  bool get rejecting => _rejecting;

  // ===== Desglose por solicitud =====
  final Map<int, CommissionRequestBreakdown> _breakdownCache = {};
  CommissionRequestBreakdown? _currentBreakdown;
  bool _loadingBreakdown = false;
  String? _breakdownError;

  CommissionRequestBreakdown? get currentBreakdown => _currentBreakdown;
  bool get loadingBreakdown => _loadingBreakdown;
  String? get breakdownError => _breakdownError;

  void clearBreakdown() {
    _currentBreakdown = null;
    _breakdownError = null;
    _loadingBreakdown = false;
    notifyListeners();
  }

  Future<CommissionRequestBreakdown?> loadCommissionBreakdown(
    int requestId, {
    bool force = false,
  }) async {
    if (!force && _breakdownCache.containsKey(requestId)) {
      _currentBreakdown = _breakdownCache[requestId];
      _breakdownError = null;
      _loadingBreakdown = false;
      notifyListeners();
      return _currentBreakdown;
    }

    _loadingBreakdown = true;
    _breakdownError = null;
    _currentBreakdown = null;
    notifyListeners();

    try {
      final br = await api.fetchCommissionBreakdown(requestId);
      _breakdownCache[requestId] = br;
      _currentBreakdown = br;
      return br;
    } catch (e, st) {
      debugPrint('loadCommissionBreakdown ERROR: $e\n$st');
      _breakdownError = e.toString();
      _currentBreakdown = null;
      return null;
    } finally {
      _loadingBreakdown = false;
      notifyListeners();
    }
  }

  Future<void> rejectSelected(List<int> requestIds, String reason) async {
    if (_rejecting) return;
    _rejecting = true;
    notifyListeners();

    final failures = <int, Object>{};

    try {
      // Llamadas secuenciales: más seguras si el backend toca saldos en transacción.
      for (final id in requestIds) {
        try {
          await api.rejectPayoutRequest(id: id, reason: reason);
        } catch (e) {
          failures[id] = e;
        }
      }

      if (failures.isNotEmpty) {
        // Lanza un error compacto para que la vista muestre Snackbar.
        final ids = failures.keys.join(', ');
        throw Exception('No se pudo rechazar: $ids');
      }
      // Refrescar listas/métricas tras rechazar
      await loadCommissions(); // por defecto traerá las actuales (puedes pasar status)
      await load(); // KPIs
    } finally {
      _rejecting = false;
      notifyListeners();
    }
  }

  Future<Map<String, dynamic>?> createPayoutBatch({
    required List<int> requestIds,
    String note = '',
    List<File> files = const [], // ✅ aquí
  }) async {
    if (_paying) return null;
    _paying = true;
    notifyListeners();

    try {
      final result = await api.createPayoutBatch(
        requestIds: requestIds,
        note: note,
        files: files, // ✅ ahora coincide con la API
      );

      await loadCommissions(status: 'requested');
      await loadPayouts();
      await load();
      return result;
    } catch (e, st) {
      debugPrint('createPayoutBatch ERROR: $e\n$st');
      rethrow;
    } finally {
      _paying = false;
      notifyListeners();
    }
  }

  Future<PayoutBatchDetails?> loadPayoutBatchDetails(
    int batchId, {
    bool force = false,
  }) async {
    if (!force && _currentBatchDetails?.batch.id == batchId) {
      _batchDetailsError = null;
      _loadingBatchDetails = false;
      notifyListeners();
      return _currentBatchDetails;
    }

    _loadingBatchDetails = true;
    _batchDetailsError = null;
    _currentBatchDetails = null;
    notifyListeners();

    try {
      final details = await api.fetchPayoutBatchDetails(batchId);
      _currentBatchDetails = details;
      return details;
    } catch (e, st) {
      debugPrint('loadPayoutBatchDetails ERROR: $e\n$st');
      _batchDetailsError = e.toString();
      return null;
    } finally {
      _loadingBatchDetails = false;
      notifyListeners();
    }
  }
}
