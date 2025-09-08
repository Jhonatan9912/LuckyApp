// lib/presentation/screens/admin_dashboard/widgets/referrals_bottom_sheet.dart
import 'package:flutter/material.dart';
import 'package:base_app/presentation/screens/admin_dashboard/logic/referrals_controller.dart';
import 'package:base_app/data/api/admin_referrals_api.dart';
import 'package:base_app/data/api/api_service.dart';
import 'package:base_app/data/models/top_referrer.dart'; // 👈 NUEVO
import 'package:base_app/domain/models/commission_request.dart';
import 'package:base_app/presentation/screens/admin_dashboard/widgets/user_detail_sheet.dart';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:base_app/data/models/payout_batch.dart';
import 'package:base_app/data/models/payout_batch_detail.dart';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:base_app/data/session/session_manager.dart';

class ReferralsBottomSheet extends StatefulWidget {
  const ReferralsBottomSheet({
    super.key,
    // Callbacks opcionales (no lógica acá)
    this.onPaySelected,
    this.onOpenUser,
    this.onToggleSelectCommission,
    this.onMarkAsPaid,
  });

  /// Pagar las comisiones seleccionadas (futuro: lista de ids)
  final VoidCallback? onPaySelected;

  /// Ver el detalle de un usuario referido
  final void Function(int userId)? onOpenUser;

  /// Seleccionar/deseleccionar una comisión
  final void Function(int commissionId, bool selected)?
  onToggleSelectCommission;

  /// Marcar un payout como pagado
  final void Function(int payoutId)? onMarkAsPaid;

  @override
  State<ReferralsBottomSheet> createState() => _ReferralsBottomSheetState();
}

class _ReferralsBottomSheetState extends State<ReferralsBottomSheet> {
  late final ReferralsController _ctrl;
  // ignore: prefer_final_fields
  String? _statusFilter = 'requested';

  @override
  void initState() {
    super.initState();

    // 👇 aquí va exactamente
    _ctrl = ReferralsController(
      api: AdminReferralsApi(baseUrl: ApiService.defaultBaseUrl),
    );

    _ctrl.load(); // <- carga el resumen (no uses loadSummary)
    _ctrl.loadTop();
    _ctrl.loadCommissions(status: _statusFilter);
    debugPrint(
      '[ReferralsBottomSheet] initState -> load(), loadTop(), loadCommissions(status=$_statusFilter)',
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.92,
      minChildSize: 0.5,
      maxChildSize: 0.98,
      builder: (ctx, scroll) {
        return ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          child: Material(
            color: Theme.of(context).scaffoldBackgroundColor,
            child: Column(
              children: [
                const _Handle(),
                const SizedBox(height: 4),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      Icon(Icons.groups_2_outlined, color: Colors.deepPurple),
                      const SizedBox(width: 8),
                      Text(
                        'Referidos & Comisiones',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const Spacer(),
                      IconButton(
                        tooltip: 'Cerrar',
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                const Divider(height: 1),

                // Tabs
                const _Tabs(),

                // Contenido tabs
                Expanded(
                  child: AnimatedBuilder(
                    animation: _ctrl,
                    builder: (_, __) {
                      final s = _ctrl.summary;
                      final loading = _ctrl.loading;
                      final err = _ctrl.error;

                      return TabBarView(
                        children: [
                          // 1) Resumen (dinámico)
                          _SummaryTab(
                            scrollController: scroll,
                            loading: loading,
                            error: err,
                            total: s?.total ?? 0,
                            active: s?.active ?? 0,
                            inactive: s?.inactive ?? 0,
                            comisionPendiente: _ctrl.pendingLabel,
                            comisionPagada: _ctrl.paidLabel,
                            top: _ctrl.top, // 👈 NUEVO
                          ),

                          // 2) Comisiones (pendientes) — por ahora maqueta
                          _CommissionsTab(
                            scrollController: scroll,
                            items: _ctrl.commissions,
                            loading: _ctrl.loadingCommissions,
                            error: _ctrl.commissionsError,
                            onToggleSelect: (id, selected) {
                              // Buscar el item sin usar .empty()
                              CommissionRequest? found;
                              for (final e in _ctrl.commissions) {
                                if (e.id == id) {
                                  found = e;
                                  break;
                                }
                              }
                              final amount = found?.amountCop ?? 0.0;
                              _handleToggleSelect(id, selected, amount);
                            },
                            onOpenUser: (uid, rid) =>
                                _openUserDetail(context, uid, rid),
                          ),

                          // 3) Pagos (lista real sin botón "Marcar pagado")
                          _PayoutsTab(scrollController: scroll),
                        ],
                      );
                    },
                  ),
                ),

                // Barra de acciones fija para pagar seleccionados (maqueta)
                SafeArea(
                  top: false,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: Theme.of(context).cardColor,
                      boxShadow: const [
                        BoxShadow(
                          blurRadius: 8,
                          offset: Offset(0, -2),
                          color: Color(0x14000000),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        // Resumen selección
                        Expanded(
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: _selectedIds.isEmpty
                                ? const _SelectedSummaryBadge(
                                    count: 0,
                                    total: '\$0',
                                  )
                                : _SelectedSummaryBadge(
                                    count: _selectedIds.length,
                                    total: _fmtCop(_selectedTotal),
                                  ),
                          ),
                        ),
                        const SizedBox(width: 8),

                        // Botón Rechazar (solo si hay selección)
                        if (_selectedIds.isNotEmpty) ...[
                          OutlinedButton.icon(
                            onPressed: (_selectedIds.isEmpty || _ctrl.rejecting)
                                ? null
                                : _handleRejectSelected,
                            icon: const Icon(Icons.block),
                            label: Text(
                              _ctrl.rejecting ? 'Rechazando…' : 'Rechazar',
                            ),
                            style: OutlinedButton.styleFrom(
                              minimumSize: const Size(0, 44),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                              ),
                              foregroundColor: Colors.red.shade700,
                              side: BorderSide(color: Colors.red.shade200),
                            ),
                          ),

                          const SizedBox(width: 8),
                        ],

                        // Botón Pagar
                        FilledButton.icon(
                          onPressed:
                              (_selectedIds.isNotEmpty &&
                                  !_ctrl.rejecting /* && !_ctrl.paying */ )
                              ? _handlePaySelected
                              : null,
                          icon: const Icon(Icons.payments_outlined),
                          label: const Text('Pagar seleccionados'),
                          style: FilledButton.styleFrom(
                            minimumSize: const Size(0, 44),
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _openUserDetail(
    BuildContext context,
    int userId,
    int requestId,
  ) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.75,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          builder: (ctx, scroll) {
            return ClipRRect(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(24),
              ),
              child: UserDetailSheet(
                ctrl: _ctrl,
                userId: userId,
                requestId: requestId, // 👈 ahora sí
              ),
            );
          },
        );
      },
    );
  }

  // --- selección local de solicitudes ---
  final Set<int> _selectedIds = <int>{};
  double _selectedTotal = 0;

  // formatea COP sin decimales
  String _fmtCop(double v) {
    final s = v.toStringAsFixed(0);
    final re = RegExp(r'\B(?=(\d{3})+(?!\d))');
    return '\$${s.replaceAllMapped(re, (m) => '.')}';
  }

  // manejar toggle desde cada tile
  void _handleToggleSelect(int id, bool selected, double amountCop) {
    setState(() {
      if (selected) {
        if (_selectedIds.add(id)) _selectedTotal += amountCop;
      } else {
        if (_selectedIds.remove(id)) _selectedTotal -= amountCop;
      }
    });

    // si te pasaron callback externo, notifícalo
    widget.onToggleSelectCommission?.call(id, selected);
  }

  // acciones
  Future<void> _handlePaySelected() async {
    if (_selectedIds.isEmpty) return;

    // 1) Abre modal para nota + adjuntos
    final result = await showModalBottomSheet<_PayBatchResult>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => _PaySelectedSheet(
        preselectedCount: _selectedIds.length,
        preselectedTotalLabel: _fmtCop(_selectedTotal),
      ),
    );

    if (!mounted || result == null) return;

    // 2) Loading ligero
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      // 3) Llama al controller para crear el lote y marcar pagadas
      final out = await _ctrl.createPayoutBatch(
        requestIds: _selectedIds.toList(),
        note: result.note,
        files: result.files,
      );

      if (!mounted) return;
      Navigator.pop(context); // cierra loading

      // 4) Limpia selección local y refresca listas
      setState(() {
        _selectedIds.clear();
        _selectedTotal = 0;
      });
      await _ctrl.loadCommissions(status: _statusFilter);
      await _ctrl.load();

      // 5) Feedback
      if (!mounted) return;
      final batchId = out?['batch_id'];
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Pago creado (lote #$batchId). Solicitudes marcadas como pagadas.',
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        Navigator.pop(context); // cierra loading
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('No se pudo crear el pago: $e')));
      }
    }
  }

  void _handleRejectSelected() async {
    if (_selectedIds.isEmpty || _ctrl.rejecting) return;

    // 1) Pedimos el motivo en un modal con formulario
    final reason = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => const _RejectReasonSheet(),
    );

    if (!mounted || reason == null || reason.trim().isEmpty) return;

    // 2) (Opcional) loading simple
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      // 3) Llama a tu controller para rechazar en backend
      await _ctrl.rejectSelected(_selectedIds.toList(), reason.trim());

      if (!mounted) return;
      Navigator.pop(context); // cierra loading

      // 4) Limpia selección y refresca
      setState(() {
        _selectedIds.clear();
        _selectedTotal = 0;
      });
      _ctrl.loadCommissions(status: _statusFilter);
      _ctrl.load(); // KPIs

      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Solicitudes rechazadas')));
    } catch (e) {
      if (mounted) {
        Navigator.pop(context); // cierra loading
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('No se pudo rechazar: $e')));
      }
    }
  }
}

// ———— Sub-widgets de UI (solo visual) ————

class _Handle extends StatelessWidget {
  const _Handle();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 24,
      alignment: Alignment.center,
      child: Container(
        width: 40,
        height: 5,
        decoration: BoxDecoration(
          color: Colors.black12,
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    );
  }
}

class _PayoutsFiltersRow extends StatelessWidget {
  const _PayoutsFiltersRow({required this.selected, required this.onChange});

  final PayoutsFilter selected;
  final void Function(PayoutsFilter value) onChange;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: -6,
      children: [
        _PayoutsChip(
          label: 'Todos',
          selected: selected == PayoutsFilter.all,
          onTap: () => onChange(PayoutsFilter.all),
        ),
        _PayoutsChip(
          label: 'Hoy',
          selected: selected == PayoutsFilter.today,
          onTap: () => onChange(PayoutsFilter.today),
        ),
        _PayoutsChip(
          label: 'Este mes',
          selected: selected == PayoutsFilter.month,
          onTap: () => onChange(PayoutsFilter.month),
        ),
        _PayoutsChip(
          label: 'Últimos 3 meses',
          selected: selected == PayoutsFilter.last3,
          onTap: () => onChange(PayoutsFilter.last3),
        ),
        _PayoutsChip(
          label: 'Este año',
          selected: selected == PayoutsFilter.year,
          onTap: () => onChange(PayoutsFilter.year),
        ),
      ],
    );
  }
}

class _PayoutsChip extends StatelessWidget {
  const _PayoutsChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return FilterChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
    );
  }
}

class _Tabs extends StatelessWidget {
  const _Tabs();
  @override
  Widget build(BuildContext context) {
    return const TabBar(
      isScrollable: true,
      tabs: [
        Tab(text: 'Resumen'),
        Tab(text: 'Comisiones'),
        Tab(text: 'Pagos'),
      ],
    );
  }
}

class _SummaryTab extends StatelessWidget {
  const _SummaryTab({
    required this.scrollController,
    required this.loading,
    required this.error,
    required this.total,
    required this.active,
    required this.inactive,
    required this.comisionPendiente,
    required this.comisionPagada,
    required this.top, // 👈 NUEVO
  });

  final ScrollController scrollController;
  final bool loading;
  final String? error;
  final int total;
  final int active;
  final int inactive;
  final String comisionPendiente;
  final String comisionPagada;
  final List<TopReferrer> top;

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return ListView(
        controller: scrollController,
        padding: const EdgeInsets.all(16),
        children: const [
          Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: CircularProgressIndicator(),
            ),
          ),
        ],
      );
    }

    if (error != null) {
      return ListView(
        controller: scrollController,
        padding: const EdgeInsets.all(16),
        children: [
          const SizedBox(height: 8),
          Text(
            'No se pudo cargar el resumen:',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 8),
          Text(error!, style: const TextStyle(color: Colors.red)),
          const SizedBox(height: 16),
          const Text('Intenta refrescar más tarde.'),
        ],
      );
    }

    return ListView(
      controller: scrollController,
      padding: const EdgeInsets.all(16),
      children: [
        _SummaryHeader(
          totalReferidos: '$total',
          activos: '$active',
          inactivos: '$inactive',
          comisionPendiente: comisionPendiente,
          comisionPagada: comisionPagada,
        ),

        const SizedBox(height: 12),
        const _SectionTitle('Top Referidos'),
        const SizedBox(height: 8),
        if (top.isEmpty)
          const Text('No hay datos aún.')
        else
          ...top.map(
            (t) => _ReferralCard(
              name: t.name,
              phone:
                  '${t.phone} • ${t.activeCount} ${t.activeCount == 1 ? 'activo' : 'activos'}',
              status: t.status, // ← ahora muestra FREE/PRO
            ),
          ),
      ],
    );
  }
}

class _CommissionsTab extends StatelessWidget {
  const _CommissionsTab({
    required this.scrollController,
    required this.items,
    required this.loading,
    this.error,
    this.onToggleSelect,
    this.onOpenUser,
  });

  final ScrollController scrollController;
  final List<CommissionRequest> items;
  final bool loading;
  final String? error;
  final void Function(int id, bool selected)? onToggleSelect;
  final void Function(int userId, int requestId)? onOpenUser;

  String _fmtCop(double v) {
    final s = v.toStringAsFixed(0);
    final re = RegExp(r'\B(?=(\d{3})+(?!\d))');
    return '\$${s.replaceAllMapped(re, (m) => '.')}';
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return ListView(
        controller: scrollController,
        padding: const EdgeInsets.all(16),
        children: const [
          SizedBox(height: 8),
          Center(child: CircularProgressIndicator()),
        ],
      );
    }

    if (error != null) {
      return ListView(
        controller: scrollController,
        padding: const EdgeInsets.all(16),
        children: [
          const _SectionTitle('Pendientes por pagar'),
          const SizedBox(height: 8),
          Text(
            'Error cargando comisiones: $error',
            style: const TextStyle(color: Colors.red),
          ),
        ],
      );
    }

    if (items.isEmpty) {
      return ListView(
        controller: scrollController,
        padding: const EdgeInsets.all(16),
        children: const [
          _SectionTitle('Pendientes por pagar'),
          SizedBox(height: 8),
          Text('No hay solicitudes por ahora.'),
        ],
      );
    }

    return ListView(
      controller: scrollController,
      padding: const EdgeInsets.all(16),
      children: [
        const _SectionTitle('Pendientes por pagar'),
        const SizedBox(height: 8),
        ...items.map(
          (it) => _CommissionTile(
            id: it.id,
            userName: it.userName,
            userId: it.userId,
            month: it.monthLabel.isNotEmpty
                ? it.monthLabel
                : '${it.createdAt.day}/${it.createdAt.month}/${it.createdAt.year}',
            amount: _fmtCop(it.amountCop), // para mostrar
            amountValue: it.amountCop, // 👈 para sumar
            onOpenUser: onOpenUser,
            onToggleSelect: onToggleSelect,
          ),
        ),
      ],
    );
  }
}

// Filtro de fechas para la pestaña Pagos
enum PayoutsFilter { all, today, month, last3, year }

class _PayoutsTab extends StatefulWidget {
  const _PayoutsTab({required this.scrollController});
  final ScrollController scrollController;

  @override
  State<_PayoutsTab> createState() => _PayoutsTabState();
}

class _PayoutsTabState extends State<_PayoutsTab> {
  bool _requestedOnce = false;
  PayoutsFilter _payoutsFilter = PayoutsFilter.all;
  
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_requestedOnce) {
      final s = context.findAncestorStateOfType<_ReferralsBottomSheetState>();
      if (s != null) {
        s._ctrl.loadPayouts();
      }
      _requestedOnce = true;
    }
  }
  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  DateTime _startOfMonth(DateTime d) => DateTime(d.year, d.month, 1);

  // Rango inclusivo por fecha de creación
  bool _betweenInclusive(DateTime? dt, DateTime start, DateTime end) {
    if (dt == null) return false;
    final day = DateTime(dt.year, dt.month, dt.day);
    final s = DateTime(start.year, start.month, start.day);
    final e = DateTime(end.year, end.month, end.day);
    return (day.isAtSameMomentAs(s) || day.isAfter(s)) &&
           (day.isAtSameMomentAs(e) || day.isBefore(e));
  }

  List<PayoutBatch> _applyFilter(List<PayoutBatch> items) {
    final now = DateTime.now();
    switch (_payoutsFilter) {
      case PayoutsFilter.all:
        return items;

      case PayoutsFilter.today:
        return items.where((b) => _isSameDay(b.createdAt ?? DateTime(1900), now)).toList();

      case PayoutsFilter.month:
        final start = _startOfMonth(now);
        final end = now;
        return items.where((b) => _betweenInclusive(b.createdAt, start, end)).toList();

      case PayoutsFilter.last3:
        // Desde el primer día del mes de hace 2 meses (incluyendo el mes actual -> 3 meses)
        final threeMonthsAgo = DateTime(now.year, now.month - 2, 1);
        final start = _startOfMonth(threeMonthsAgo);
        final end = now;
        return items.where((b) => _betweenInclusive(b.createdAt, start, end)).toList();

      case PayoutsFilter.year:
        final y = now.year;
        return items.where((b) => (b.createdAt?.year ?? -1) == y).toList();
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.findAncestorStateOfType<_ReferralsBottomSheetState>();
    if (s == null) return const Center(child: Text('No controller'));
    final ctrl = s._ctrl;

    return AnimatedBuilder(
      animation: ctrl,
      builder: (_, __) {
        final filtersRow = Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: _PayoutsFiltersRow(
            selected: _payoutsFilter,
            onChange: (v) => setState(() => _payoutsFilter = v),
          ),
        );

        if (ctrl.loadingPayouts) {
          return ListView(
            controller: widget.scrollController,
            padding: const EdgeInsets.all(16),
            children: [
              filtersRow, // 👈 usa el filtro
              const SizedBox(height: 8),
              const Center(child: CircularProgressIndicator()),
            ],
          );
        }

        if (ctrl.payoutsError != null) {
          return ListView(
            controller: widget.scrollController,
            padding: const EdgeInsets.all(16),
            children: [
              filtersRow, // 👈 usa el filtro
              const SizedBox(height: 12),
              const _SectionTitle('Pagos realizados'),
              const SizedBox(height: 8),
              Text(
                'Error cargando pagos: ${ctrl.payoutsError}',
                style: const TextStyle(color: Colors.red),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: ctrl.loadPayouts,
                icon: const Icon(Icons.refresh),
                label: const Text('Reintentar'),
              ),
            ],
          );
        }

        final items = ctrl.payouts;
        final visible = _applyFilter(items);

        if (visible.isEmpty) {
          return ListView(
            controller: widget.scrollController,
            padding: const EdgeInsets.all(16),
            children: [
              filtersRow, // 👈 usa el filtro
              const SizedBox(height: 12),
              const _SectionTitle('Pagos realizados'),
              const SizedBox(height: 8),
               const Text('No hay lotes de pago para este filtro.'),
            ],
          );
        }

        return ListView(
          controller: widget.scrollController,
          padding: const EdgeInsets.all(16),
          children: [
            filtersRow, // 👈 usa el filtro
            const SizedBox(height: 12),
            const _SectionTitle('Pagos realizados'),
            const SizedBox(height: 8),
            ...visible.map(
              (b) => _PayoutTilePaid(
                batch: b,
                onViewDetails: () => _openBatchDetails(context, ctrl, b.id),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _openBatchDetails(
    BuildContext context,
    ReferralsController ctrl,
    int batchId,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.92,
        minChildSize: 0.5,
        maxChildSize: 0.98,
        builder: (ctx, scroll) => ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          child: _PayoutDetailsSheet(ctrl: ctrl, batchId: batchId),
        ),
      ),
    );
  }
}

class _PayoutTilePaid extends StatelessWidget {
  const _PayoutTilePaid({required this.batch, required this.onViewDetails});

  final PayoutBatch batch;
  final VoidCallback onViewDetails;

  String _fmtDate(DateTime? dt) {
    if (dt == null) return '-';
    return '${dt.day.toString().padLeft(2, '0')}/'
        '${dt.month.toString().padLeft(2, '0')}/'
        '${dt.year}';
  }

  @override
  Widget build(BuildContext context) {
    // cuántas solicitudes trae el lote (compat con modelo viejo)
    final int reqs = batch.items;

    // TÍTULO: si hay 1 solicitud -> nombre; si >1 -> "N solicitantes"
    final String title = (reqs == 1)
        ? ((batch.firstUserName?.trim().isNotEmpty ?? false)
              ? batch.firstUserName!.trim()
              : 'Usuario #${batch.firstUserId ?? batch.id}')
        : '$reqs solicitantes';

    // Fecha y etiqueta:
    //  - si el lote trae 1 solicitud y tenemos public_code del usuario -> mostrar ese código
    //  - de lo contrario, mostrar el código del lote (PB-000xxx)
    final String dateStr = _fmtDate(batch.createdAt);
    final String batchCode =
        batch.code ?? 'PB-${batch.id.toString().padLeft(6, '0')}';
    final String userCode = (batch.firstUserCode?.trim().isNotEmpty ?? false)
        ? batch.firstUserCode!.trim()
        : '';
    final String label = (reqs == 1 && userCode.isNotEmpty)
        ? userCode
        : batchCode;

    // Total (ya formateado en el modelo)
    final String totalStr = batch.totalCopLabel;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        isThreeLine: true,
        leading: CircleAvatar(
          backgroundColor: Colors.green.shade50,
          child: const Icon(Icons.check_circle, color: Colors.green),
        ),
        // 👇 deja de decir "Lote #..."
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(dateStr), // Fecha
            Text('$label • Total $totalStr'),
          ],
        ),
        trailing: FilledButton.tonal(
          onPressed: onViewDetails,
          child: const Text('Ver detalles'),
        ),
      ),
    );
  }
}

class _PayoutDetailsSheet extends StatefulWidget {
  const _PayoutDetailsSheet({required this.ctrl, required this.batchId});
  final ReferralsController ctrl;
  final int batchId;

  @override
  State<_PayoutDetailsSheet> createState() => _PayoutDetailsSheetState();
}

class _PayoutDetailsSheetState extends State<_PayoutDetailsSheet> {
  @override
  void initState() {
    super.initState();
    // Evita notificaciones durante el build
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      widget.ctrl.loadPayoutBatchDetails(widget.batchId);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: AnimatedBuilder(
        animation: widget.ctrl,
        builder: (_, __) {
          final loading = widget.ctrl.loadingBatchDetails;
          final err = widget.ctrl.batchDetailsError;
          final details = widget.ctrl.currentBatchDetails;

          return Column(
            children: [
              // Header
              Container(
                height: 24,
                alignment: Alignment.center,
                child: Container(
                  width: 40,
                  height: 5,
                  decoration: BoxDecoration(
                    color: Colors.black12,
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                child: Row(
                  children: [
                    const Icon(
                      Icons.receipt_long_outlined,
                      color: Colors.deepPurple,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Detalle del pago',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const Spacer(),
                    IconButton(
                      tooltip: 'Cerrar',
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),

              if (loading) ...[
                const SizedBox(height: 24),
                const Center(child: CircularProgressIndicator()),
                const SizedBox(height: 24),
              ] else if (err != null) ...[
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'No se pudo cargar: $err',
                    style: const TextStyle(color: Colors.red),
                  ),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () =>
                      widget.ctrl.loadPayoutBatchDetails(widget.batchId),
                  icon: const Icon(Icons.refresh),
                  label: const Text('Reintentar'),
                ),
                const SizedBox(height: 16),
              ] else if (details == null) ...[
                const SizedBox(height: 24),
                const Text('Sin datos'),
              ] else ...[
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      // Cabecera del lote
                      _SectionTitle('Lote #${details.batch.id}'),
                      const SizedBox(height: 8),
                      _KeyValueRow(
                        label: 'Fecha',
                        value: _fmtLongDate(details.batch.createdAt),
                      ),
                      _KeyValueRow(
                        label: 'Total',
                        value: details.batch.totalCopLabel,
                      ),
                      _KeyValueRow(
                        label: 'Solicitudes',
                        value: '${details.batch.items}',
                      ),
                      const SizedBox(height: 16),
                      const Divider(),
                      const SizedBox(height: 10),

                      // TODAS las solicitudes (lectura)
                      const _SectionTitle('Solicitudes'),
                      const SizedBox(height: 8),
                      ...details.requests.map(
                        (r) => _RequestReadOnlyCard(r: r),
                      ),

                      const SizedBox(height: 16),

                      // Evidencias (muestra la primera)
                      if (details.files.isNotEmpty) ...[
                        const _SectionTitle('Evidencia'),
                        const SizedBox(height: 8),
                        _buildEvidence(details),
                      ],
                    ],
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  String _fmtLongDate(DateTime? dt) {
    if (dt == null) return '-';
    final d =
        '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';
    final t =
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    return '$d • $t';
  }

  Widget _buildEvidence(PayoutBatchDetails details) {
    final f = details.files.first;

    // ✅ Usa absoluta si ya viene con http(s), si no, antepone tu base
    final base =
        ApiService.defaultBaseUrl; // debe ser http://10.0.2.2:8000 en dev
    final fullUrl = (f.url.startsWith('http')) ? f.url : '$base${f.url}';

    debugPrint('[PayoutDetails] evidence name=${f.name} url=$fullUrl');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(f.name, style: Theme.of(context).textTheme.labelMedium),
        const SizedBox(height: 8),

        // ✅ Usa imagen autenticada (con Bearer)
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: AspectRatio(
            aspectRatio: 4 / 3,
            child: _AuthImage(
              // ← ESTE widget baja la imagen con JWT
              url: fullUrl,
              width: double.infinity,
              height: double.infinity,
            ),
          ),
        ),
      ],
    );
  }
}

class _RequestReadOnlyCard extends StatelessWidget {
  const _RequestReadOnlyCard({required this.r});
  final dynamic r; // el item de details.requests

  String _fmtLongDate(DateTime? dt) {
    if (dt == null) return '-';
    final d =
        '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';
    final t =
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    return '$d • $t';
  }

  @override
  Widget build(BuildContext context) {
    final String name = ((r.userName ?? '').trim().isNotEmpty)
        ? (r.userName ?? '').trim()
        : 'Usuario #${r.userId ?? r.id}';
    final code = (r.userCode ?? '').trim();
    final doc = (r.documentId ?? '').trim();
    final date = _fmtLongDate(r.createdAt);
    final amount = r.amountLabel; // viene formateado

    return Card(
      color: const Color(0xFFFFF7EB),
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _KeyValueRow(label: 'Nombre', value: name),
            _KeyValueRow(label: 'Código', value: code.isEmpty ? '-' : code),
            _KeyValueRow(label: 'Cédula', value: doc.isEmpty ? '-' : doc),
            _KeyValueRow(label: 'Fecha de solicitud', value: date),
            _KeyValueRow(label: 'Monto', value: amount),
          ],
        ),
      ),
    );
  }
}

class _KeyValueRow extends StatelessWidget {
  const _KeyValueRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final txt = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 140,
            child: Text(
              label,
              style: txt.labelMedium?.copyWith(color: Colors.black54),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: txt.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryHeader extends StatelessWidget {
  const _SummaryHeader({
    required this.totalReferidos,
    required this.activos,
    required this.inactivos,
    required this.comisionPendiente,
    required this.comisionPagada,
  });

  final String totalReferidos;
  final String activos;
  final String inactivos;
  final String comisionPendiente;
  final String comisionPagada;

  @override
  Widget build(BuildContext context) {
    final txt = Theme.of(context).textTheme;
    return Card(
      elevation: 0,
      color: const Color(0xFFFFF7EB),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                const Icon(Icons.group_outlined, color: Colors.deepPurple),
                const SizedBox(width: 8),
                Text('Resumen de referidos', style: txt.titleMedium),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                _KpiBox(label: 'Total', value: totalReferidos),
                const SizedBox(width: 8),
                _KpiBox(label: 'Activos', value: activos),
                const SizedBox(width: 8),
                _KpiBox(label: 'Inactivos', value: inactivos),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                _KpiBox(
                  label: 'Pendiente',
                  value: comisionPendiente,
                  badge: 'COP',
                ),
                const SizedBox(width: 8),
                _KpiBox(label: 'Pagada', value: comisionPagada, badge: 'COP'),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _KpiBox extends StatelessWidget {
  const _KpiBox({required this.label, required this.value, this.badge});
  final String label;
  final String value;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    final txt = Theme.of(context).textTheme;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: const [BoxShadow(blurRadius: 8, color: Color(0x0F000000))],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: txt.labelMedium?.copyWith(color: Colors.black54),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    value, // 👈 aquí usas amount directamente
                    textAlign: TextAlign.right,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                if (badge != null) ...[
                  const SizedBox(width: 8),
                  _Badge(text: badge!), // 👈 usa el widget de abajo
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;
  @override
  Widget build(BuildContext context) {
    return Text(text, style: Theme.of(context).textTheme.titleSmall);
  }
}

class _ReferralCard extends StatelessWidget {
  const _ReferralCard({
    required this.name,
    required this.phone,
    required this.status,
  });
  final String name;
  final String phone;
  final String status;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: Colors.deepPurple.shade50,
          child: const Icon(Icons.person_outline, color: Colors.deepPurple),
        ),
        title: Text(name),
        subtitle: Text(phone),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: status == 'PRO'
                ? Colors.green.shade50
                : Colors.grey.shade200,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            status,
            style: TextStyle(
              color: status == 'PRO' ? Colors.green.shade700 : Colors.black54,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

class _CommissionTile extends StatefulWidget {
  const _CommissionTile({
    required this.id,
    required this.userName,
    required this.userId,
    required this.month,
    required this.amount,
    required this.amountValue,
    this.onOpenUser,
    this.onToggleSelect,
  });

  final int id;
  final String userName;
  final int userId;
  final String month;
  final String amount;
  final double amountValue;
  final void Function(int userId, int requestId)? onOpenUser;
  final void Function(int id, bool selected)? onToggleSelect;

  @override
  State<_CommissionTile> createState() => _CommissionTileState();
}

class _CommissionTileState extends State<_CommissionTile> {
  bool selected = false;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        // 👇 da más alto al tile automáticamente
        isThreeLine: true,
        minVerticalPadding: 12,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),

        leading: Checkbox(
          value: selected,
          onChanged: (v) {
            setState(() => selected = v ?? false);
            widget.onToggleSelect?.call(widget.id, selected);
          },
        ),

        title: Text(widget.userName),
        subtitle: Text('Periodo: ${widget.month}'),

        // dentro de _CommissionTileState.build, reemplaza SOLO el trailing:
        // 👇 reemplaza el trailing actual por este bloque
        trailing: SizedBox(
          width: 168, // un pelín más ancho ayuda a no truncar
          height: 56, // altura tope del ListTile
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              // Parte superior: ocupa el espacio disponible
              Expanded(
                child: Align(
                  alignment: Alignment.centerRight,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Monto (con elipsis por si es largo)
                      Flexible(
                        child: Text(
                          widget.amount,
                          textAlign: TextAlign.right,
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 4),
                      // Icono de desglose
                      IconButton(
                        tooltip: 'Ver desglose',
                        icon: const Icon(Icons.receipt_long_outlined, size: 18),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints.tightFor(
                          width: 28,
                          height: 28,
                        ),
                        onPressed: () {
                          final s = context
                              .findAncestorStateOfType<
                                _ReferralsBottomSheetState
                              >();
                          if (s == null) return;
                          showModalBottomSheet(
                            context: context,
                            isScrollControlled: true,
                            useSafeArea: true,
                            backgroundColor: Colors.transparent,
                            builder: (_) => DraggableScrollableSheet(
                              expand: false,
                              initialChildSize: 0.92,
                              minChildSize: 0.5,
                              maxChildSize: 0.98,
                              builder: (ctx, scroll) => ClipRRect(
                                borderRadius: const BorderRadius.vertical(
                                  top: Radius.circular(24),
                                ),
                                child: UserDetailSheet(
                                  ctrl: s._ctrl,
                                  userId: widget.userId, // solicitante
                                  requestId:
                                      widget.id, // solicitud (para el desglose)
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),

              // Separación mínima
              const SizedBox(height: 2),

              // Botón “Ver usuario” con altura contenida
              SizedBox(
                height: 24, // 🔧 baja de 28/30 -> 24 para caber en 56px total
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                  ),
                  onPressed: () =>
                      widget.onOpenUser?.call(widget.userId, widget.id),
                  child: const Text(
                    'Ver usuario',
                    style: TextStyle(fontSize: 12),
                  ), // 🔧 fuente menor
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SelectedSummaryBadge extends StatelessWidget {
  const _SelectedSummaryBadge({required this.count, required this.total});
  final int count;
  final String total;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodyMedium?.copyWith(
      color: Colors.black87,
      fontWeight: FontWeight.w600,
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.checklist_rtl, size: 18, color: Colors.black54),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            '$count seleccionadas · $total',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: style,
          ),
        ),
      ],
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 36, maxWidth: 60),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: Colors.orange.shade50,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          text,
          textAlign: TextAlign.center,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(
            context,
          ).textTheme.labelSmall?.copyWith(color: Colors.orange),
        ),
      ),
    );
  }
}

class _RejectReasonSheet extends StatefulWidget {
  const _RejectReasonSheet();

  @override
  State<_RejectReasonSheet> createState() => _RejectReasonSheetState();
}

class _RejectReasonSheetState extends State<_RejectReasonSheet> {
  final _formKey = GlobalKey<FormState>();
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final view = MediaQuery.of(context).viewInsets;
    return Padding(
      padding: EdgeInsets.only(bottom: view.bottom),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Rechazar solicitudes',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _ctrl,
                  maxLines: 4,
                  maxLength: 300,
                  decoration: const InputDecoration(
                    labelText: 'Motivo del rechazo',
                    hintText: 'Describe brevemente el motivo…',
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) {
                      return 'Escribe un motivo';
                    }
                    if (v.trim().length < 5) {
                      return 'Motivo demasiado corto';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancelar'),
                    ),
                    const SizedBox(width: 12),
                    FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.red.shade600,
                        foregroundColor: Colors.white,
                        minimumSize: const Size(100, 44),
                      ),
                      onPressed: () {
                        if (!_formKey.currentState!.validate()) return;
                        Navigator.pop(context, _ctrl.text.trim());
                      },
                      child: const Text('Rechazar'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PayBatchResult {
  final String note;
  final List<File> files;
  const _PayBatchResult({required this.note, required this.files});
}

class _PaySelectedSheet extends StatefulWidget {
  const _PaySelectedSheet({
    required this.preselectedCount,
    required this.preselectedTotalLabel,
  });

  final int preselectedCount;
  final String preselectedTotalLabel;

  @override
  State<_PaySelectedSheet> createState() => _PaySelectedSheetState();
}

class _PaySelectedSheetState extends State<_PaySelectedSheet> {
  final _formKey = GlobalKey<FormState>();
  final _noteCtrl = TextEditingController();
  final List<File> _files = [];

  @override
  void dispose() {
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickFiles() async {
    final res = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      withReadStream: false,
      withData: false,
    );
    if (res == null) return;

    final paths = res.files.map((f) => f.path).whereType<String>().toList();
    setState(() {
      for (final p in paths) {
        final f = File(p);
        if (f.existsSync()) _files.add(f);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final view = MediaQuery.of(context).viewInsets;
    return Padding(
      padding: EdgeInsets.only(bottom: view.bottom),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.payments_outlined,
                      color: Colors.deepPurple,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Confirmar pago de seleccionados',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const Spacer(),
                    _Badge(text: '${widget.preselectedCount}'),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Total a pagar: ${widget.preselectedTotalLabel}',
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 12),

                TextFormField(
                  controller: _noteCtrl,
                  maxLines: 3,
                  maxLength: 300,
                  decoration: const InputDecoration(
                    labelText: 'Nota (opcional)',
                    hintText: 'Ej. Transferencia Banco X #123…',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),

                // Adjuntos
                Row(
                  children: [
                    OutlinedButton.icon(
                      onPressed: _pickFiles,
                      icon: const Icon(Icons.attach_file_outlined),
                      label: const Text('Adjuntar evidencia'),
                    ),
                    const SizedBox(width: 12),
                    if (_files.isNotEmpty)
                      Expanded(
                        child: Text(
                          _files
                              .map(
                                (f) =>
                                    f.path.split(Platform.pathSeparator).last,
                              )
                              .join(' • '),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                ),

                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancelar'),
                    ),
                    const SizedBox(width: 12),
                    FilledButton.icon(
                      icon: const Icon(Icons.check),
                      onPressed: () {
                        if (!_formKey.currentState!.validate()) return;
                        Navigator.pop(
                          context,
                          _PayBatchResult(
                            note: _noteCtrl.text.trim(),
                            files: List<File>.from(_files),
                          ),
                        );
                      },
                      label: const Text('Confirmar pago'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ⬇⬇⬇ pega aquí, al final del archivo
class _AuthImage extends StatefulWidget {
  final String url;
  final double width;
  final double height;
  const _AuthImage({required this.url, this.width = 220, this.height = 160});

  @override
  State<_AuthImage> createState() => _AuthImageState();
}

class _AuthImageState extends State<_AuthImage> {
  Uint8List? _bytes;
  bool _error = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final token = await SessionManager().getToken();
      debugPrint('[AuthImage] GET ${widget.url} with token=${token != null}');
      final res = await http.get(
        Uri.parse(widget.url),
        headers: token != null ? {'Authorization': 'Bearer $token'} : {},
      );
      debugPrint(
        '[AuthImage] status=${res.statusCode}, bytes=${res.bodyBytes.length}',
      );
      if (res.statusCode >= 200 && res.statusCode < 300) {
        setState(() => _bytes = res.bodyBytes);
      } else {
        setState(() => _error = true);
      }
    } catch (_) {
      setState(() => _error = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error) {
      return Container(
        width: widget.width,
        height: widget.height,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.black12,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Icon(Icons.broken_image_outlined),
      );
    }
    if (_bytes == null) {
      return Container(
        width: widget.width,
        height: widget.height,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.black12,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const CircularProgressIndicator(strokeWidth: 2),
      );
    }
    return Image.memory(
      _bytes!,
      width: widget.width,
      height: widget.height,
      fit: BoxFit.cover,
    );
  }
}
