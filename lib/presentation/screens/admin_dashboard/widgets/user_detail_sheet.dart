// lib/presentation/screens/admin_dashboard/widgets/user_detail_sheet.dart
import 'package:flutter/material.dart';
import 'package:base_app/presentation/screens/admin_dashboard/logic/referrals_controller.dart';
import 'package:base_app/data/models/admin_user_detail.dart';
import 'package:base_app/data/models/commission_breakdown.dart';

class UserDetailSheet extends StatefulWidget {
  const UserDetailSheet({
    super.key,
    required this.ctrl,
    required this.userId,
    required this.requestId, // 👈 NUEVO: id de la solicitud para el desglose
  });

  final ReferralsController ctrl;
  final int userId;
  final int requestId;

  @override
  State<UserDetailSheet> createState() => _UserDetailSheetState();
}

class _UserDetailSheetState extends State<UserDetailSheet> {
  @override
  void initState() {
    super.initState();
    // Carga en paralelo: datos del solicitante + desglose de la solicitud
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await Future.wait([
        widget.ctrl.loadUserDetail(widget.userId, force: true),
        widget.ctrl.loadCommissionBreakdown(widget.requestId, force: true),
      ]);
    });
  }

  @override
  void dispose() {
    widget.ctrl.clearUserDetail();
    widget.ctrl.clearBreakdown();
    super.dispose();
  }

  String _fmtCop(int v) {
    final s = v.toString();
    final re = RegExp(r'\B(?=(\d{3})+(?!\d))');
    return '\$${s.replaceAllMapped(re, (m) => '.')}';
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.ctrl,
      builder: (_, __) {
        final uLoading = widget.ctrl.loadingUserDetail;
        final uError = widget.ctrl.userDetailError;
        final AdminUserDetail? u = widget.ctrl.currentUserDetail;

        final bLoading = widget.ctrl.loadingBreakdown;
        final bError = widget.ctrl.breakdownError;
        final CommissionRequestBreakdown? b = widget.ctrl.currentBreakdown;

        return SafeArea(
          top: false,
          child: Material(
            color: Theme.of(context).scaffoldBackgroundColor,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Column(
                children: [
                  // handle
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
                  Row(
                    children: [
                      const Icon(
                        Icons.person_search_outlined,
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
                  const SizedBox(height: 8),

                  // ====== Bloque: Usuario + Cuenta ======
                  if (uLoading)
                    const _LoadingCard()
                  else if (uError != null)
                    _ErrorCard(error: uError)
                  else if (u != null) ...[
                    _UserInfoCard(data: u),
                    const SizedBox(height: 10),
                    _BankInfoCard(data: u),
                  ] else
                    const _EmptyMsg('No hay datos del usuario.'),

                  const SizedBox(height: 12),

                  // ====== Bloque: Desglose ======
                  if (bLoading)
                    const _LoadingCard()
                  else if (bError != null)
                    _ErrorCard(error: bError)
                  else if (b != null) ...[
                    _BreakdownHeader(b: b, fmt: _fmtCop),
                    if (b.adminNote.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Card(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(
                                Icons.comment_outlined,
                                color: Colors.deepPurple,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  b.adminNote,
                                  style: Theme.of(context).textTheme.bodyMedium,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],

                    const SizedBox(height: 8),
                    Expanded(
                      child: _BreakdownList(items: b.items, fmt: _fmtCop),
                    ),
                  ] else
                    const SizedBox(
                      height: 120,
                      child: _EmptyMsg('Sin desglose disponible.'),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _EmptyMsg extends StatelessWidget {
  const _EmptyMsg(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(padding: const EdgeInsets.all(12), child: Text(text)),
  );
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.error});
  final String error;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Colors.red.shade50,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.error_outline, color: Colors.red),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Ocurrió un error.\n$error',
                style: const TextStyle(color: Colors.red),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _UserInfoCard extends StatelessWidget {
  const _UserInfoCard({required this.data});
  final AdminUserDetail data;

  @override
  Widget build(BuildContext context) {
    final pro = data.isPro;
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.badge_outlined, color: Colors.deepPurple),
                const SizedBox(width: 8),
                Text('Usuario', style: Theme.of(context).textTheme.titleSmall),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: pro ? Colors.green.shade50 : Colors.grey.shade200,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    pro ? 'PRO' : 'FREE',
                    style: TextStyle(
                      color: pro ? Colors.green.shade700 : Colors.black54,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _Kvp(label: 'Nombre completo', value: data.fullName),
            _Kvp(label: 'Identificación', value: data.idNumber),

            if ((data.observations ?? '').isNotEmpty) ...[
              const SizedBox(height: 6), // 👈 separador
              _Kvp(label: 'Observación', value: data.observations!),
            ],
          ],
        ),
      ),
    );
  }
}

class _BankInfoCard extends StatelessWidget {
  const _BankInfoCard({required this.data});
  final AdminUserDetail data;

  @override
  Widget build(BuildContext context) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.account_balance_outlined,
                  color: Colors.deepPurple,
                ),
                const SizedBox(width: 8),
                Text(
                  'Cuenta de pago',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ],
            ),
            const SizedBox(height: 8),
            _Kvp(
              label: 'Tipo',
              value: data.accountType.isEmpty ? '-' : data.accountType,
            ),
            _Kvp(
              label: 'Proveedor',
              value: data.providerName.isEmpty ? '-' : data.providerName,
            ),
            if ((data.bankKind ?? '').isNotEmpty)
              _Kvp(label: 'Tipo de cuenta', value: data.bankKind!),
            _Kvp(
              label: 'Número',
              value: data.accountNumber.isEmpty ? '-' : data.accountNumber,
            ),
          ],
        ),
      ),
    );
  }
}

class _BreakdownHeader extends StatelessWidget {
  const _BreakdownHeader({required this.b, required this.fmt});
  final CommissionRequestBreakdown b;
  final String Function(int) fmt;

  @override
  Widget build(BuildContext context) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            const Icon(Icons.receipt_long_outlined, color: Colors.deepPurple),
            const SizedBox(width: 8),
            Expanded(
              child: Wrap(
                spacing: 16,
                runSpacing: 6,
                children: [
                  _kv('Solicitud', '#${b.requestId}'),
                  _kv('Solicitado', fmt(b.requestedCop)),
                  _kv('Suma items', fmt(b.itemsTotalCop)),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: b.matchesRequest
                    ? Colors.green.shade50
                    : Colors.red.shade50,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                b.matchesRequest ? 'COINCIDE' : 'NO COINCIDE',
                style: TextStyle(
                  color: b.matchesRequest
                      ? Colors.green.shade700
                      : Colors.red.shade700,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _kv(String k, String v) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text('$k: ', style: const TextStyle(color: Colors.black54)),
      Text(v, style: const TextStyle(fontWeight: FontWeight.w700)),
    ],
  );
}

class _BreakdownList extends StatelessWidget {
  const _BreakdownList({required this.items, required this.fmt});
  final List<CommissionBreakdownItem> items;
  final String Function(int) fmt;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(12),
          child: Text('Sin referidos que generen comisión.'),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.only(bottom: 16),
      itemCount: items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) {
        final it = items[i];
        return Card(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 8,
            ),
            title: Row(
              children: [
                Expanded(
                  child: Text(
                    '${it.publicCode} • ${it.name}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: it.isPro
                        ? Colors.green.shade50
                        : Colors.grey.shade200,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    it.isPro ? 'PRO' : 'FREE',
                    style: TextStyle(
                      color: it.isPro ? Colors.green.shade700 : Colors.black54,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            subtitle: Text('Cédula: ${it.idNumber}'),
            trailing: Text(
              fmt(it.commissionCop),
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
            ),
          ),
        );
      },
    );
  }
}

class _Kvp extends StatelessWidget {
  const _Kvp({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final styleLabel = Theme.of(
      context,
    ).textTheme.labelMedium?.copyWith(color: Colors.black54);
    final styleValue = Theme.of(
      context,
    ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          SizedBox(width: 160, child: Text(label, style: styleLabel)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              style: styleValue,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _LoadingCard extends StatelessWidget {
  const _LoadingCard();

  @override
  Widget build(BuildContext context) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Cargando...',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
