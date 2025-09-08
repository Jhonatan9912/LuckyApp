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
  String? _statusFilter =
      'requested'; // null=Todos | 'requested'=Pendientes | 'paid'=Pagados

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
                _FiltersRow(
                  selectedStatus: _statusFilter,
                  onChange: (newStatus) {
                    setState(() => _statusFilter = newStatus);
                    _ctrl.loadCommissions(status: newStatus);
                  },
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

                          // 3) Pagos (histórico / pendientes por confirmar) — por ahora maqueta
                          _PayoutsTab(
                            scrollController: scroll,
                            onMarkAsPaid: widget.onMarkAsPaid,
                          ),
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

class _FiltersRow extends StatelessWidget {
  const _FiltersRow({required this.selectedStatus, required this.onChange});

  /// null = Todos, 'requested' = Pendientes, 'paid' = Pagados
  final String? selectedStatus;
  final void Function(String? newStatus) onChange;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Wrap(
        spacing: 8,
        runSpacing: -6,
        children: [
          _Chip(
            label: 'Todos',
            selected: selectedStatus == null,
            onTap: () => onChange(null),
          ),
          _Chip(
            label: 'Pendientes',
            selected: selectedStatus == 'requested',
            onTap: () => onChange('requested'),
          ),
          _Chip(
            label: 'Pagados',
            selected: selectedStatus == 'paid',
            onTap: () => onChange('paid'),
          ),
          _Chip(
            label: 'Este mes',
            selected: false,
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Filtro por fecha: próximamente')),
              );
            },
          ),
          _Chip(
            label: 'Últimos 90 días',
            selected: false,
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Filtro por fecha: próximamente')),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
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
      selected: selected,
      onSelected: (_) => onTap(),
      label: Text(label),
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

class _PayoutsTab extends StatelessWidget {
  const _PayoutsTab({required this.scrollController, this.onMarkAsPaid});
  final ScrollController scrollController;
  final void Function(int payoutId)? onMarkAsPaid;

  @override
  Widget build(BuildContext context) {
    return ListView(
      controller: scrollController,
      padding: const EdgeInsets.all(16),
      children: [
        const _SectionTitle('Pagos realizados / por confirmar'),
        const SizedBox(height: 8),
        _PayoutTile(
          payoutId: 501,
          date: '01 Sep 2025',
          items: 3,
          total: '\$45.000',
          stateLabel: 'Transferencia enviada',
          onMarkAsPaid: onMarkAsPaid,
        ),
        _PayoutTile(
          payoutId: 502,
          date: '15 Ago 2025',
          items: 7,
          total: '\$105.000',
          stateLabel: 'Completado',
          completed: true,
          onMarkAsPaid: onMarkAsPaid,
        ),
      ],
    );
  }
}

// ———— Cards/ListTiles estilizados ————

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

class _PayoutTile extends StatelessWidget {
  const _PayoutTile({
    required this.payoutId,
    required this.date,
    required this.items,
    required this.total,
    required this.stateLabel,
    this.completed = false,
    this.onMarkAsPaid,
  });

  final int payoutId;
  final String date;
  final int items;
  final String total;
  final String stateLabel;
  final bool completed;
  final void Function(int payoutId)? onMarkAsPaid;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: completed
              ? Colors.green.shade50
              : Colors.orange.shade50,
          child: Icon(
            completed ? Icons.check_circle : Icons.schedule_send,
            color: completed ? Colors.green : Colors.orange,
          ),
        ),
        title: Text('Lote #$payoutId • $date'),
        subtitle: Text('$items comisiones • Total $total'),
        trailing: completed
            ? const SizedBox.shrink()
            : FilledButton.tonal(
                onPressed: () => onMarkAsPaid?.call(payoutId),
                child: const Text('Marcar pagado'),
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
