import 'package:flutter/material.dart';
import 'package:base_app/presentation/screens/admin_dashboard/logic/referrals_controller.dart';
import 'package:base_app/data/models/commission_breakdown.dart';

class CommissionBreakdownSheet extends StatefulWidget {
  const CommissionBreakdownSheet({
    super.key,
    required this.ctrl,
    required this.requestId,
  });

  final ReferralsController ctrl;
  final int requestId;

  @override
  State<CommissionBreakdownSheet> createState() => _CommissionBreakdownSheetState();
}

class _CommissionBreakdownSheetState extends State<CommissionBreakdownSheet> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.ctrl.loadCommissionBreakdown(widget.requestId, force: true);
    });
  }

  @override
  void dispose() {
    widget.ctrl.clearBreakdown();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.ctrl,
      builder: (_, __) {
        final loading = widget.ctrl.loadingBreakdown;
        final error = widget.ctrl.breakdownError;
        final data = widget.ctrl.currentBreakdown;

        return SafeArea(
          top: false,
          child: Material(
            color: Theme.of(context).scaffoldBackgroundColor,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
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
                      const Icon(Icons.receipt_long_outlined, color: Colors.deepPurple),
                      const SizedBox(width: 8),
                      Text('Desglose de la solicitud', style: Theme.of(context).textTheme.titleMedium),
                      const Spacer(),
                      IconButton(
                        tooltip: 'Cerrar',
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  if (loading) ...[
                    const SizedBox(height: 24),
                    const Center(child: CircularProgressIndicator()),
                    const SizedBox(height: 24),
                  ] else if (error != null) ...[
                    _ErrorCard(error: error),
                  ] else if (data != null) ...[
                    _HeaderSummary(b: data),
                    const SizedBox(height: 12),
                    Expanded(
                      child: _ItemsList(items: data.items),
                    ),
                    const SizedBox(height: 8),
                    _FooterMatch(b: data),
                  ] else ...[
                    const Text('No hay datos para mostrar.'),
                    const SizedBox(height: 8),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _HeaderSummary extends StatelessWidget {
  const _HeaderSummary({required this.b});
  final CommissionRequestBreakdown b;

  String _fmtCop(int v) {
    final s = v.toString();
    final re = RegExp(r'\B(?=(\d{3})+(?!\d))');
    return '\$${s.replaceAllMapped(re, (m) => '.')}';
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            const Icon(Icons.summarize_outlined, color: Colors.deepPurple),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Solicitud #${b.requestId}', style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 16,
                    runSpacing: 4,
                    children: [
                      _kv('Solicitado', _fmtCop(b.requestedCop)),
                      _kv('Suma de items', _fmtCop(b.itemsTotalCop)),
                      _kv('Moneda', b.currency),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: b.matchesRequest ? Colors.green.shade50 : Colors.red.shade50,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Row(
                children: [
                  Icon(
                    b.matchesRequest ? Icons.verified : Icons.error_outline,
                    size: 18,
                    color: b.matchesRequest ? Colors.green : Colors.red,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    b.matchesRequest ? 'COINCIDE' : 'NO COINCIDE',
                    style: TextStyle(
                      color: b.matchesRequest ? Colors.green.shade700 : Colors.red.shade700,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _kv(String k, String v) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('$k: ', style: const TextStyle(color: Colors.black54)),
        Text(v, style: const TextStyle(fontWeight: FontWeight.w700)),
      ],
    );
  }
}

class _ItemsList extends StatelessWidget {
  const _ItemsList({required this.items});
  final List<CommissionBreakdownItem> items;

  String _fmtCop(int v) {
    final s = v.toString();
    final re = RegExp(r'\B(?=(\d{3})+(?!\d))');
    return '\$${s.replaceAllMapped(re, (m) => '.')}';
    }

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const Center(child: Text('Sin items de comisión.'));
    }
    return ListView.separated(
      itemCount: items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, i) {
        final it = items[i];
        return Card(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            leading: CircleAvatar(
              child: Text(
                it.publicCode.isNotEmpty ? it.publicCode.substring(0, 1) : '#',
              ),
            ),
            title: Row(
              children: [
                Expanded(
                  child: Text('${it.publicCode} • ${it.name}', maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: it.isPro ? Colors.green.shade50 : Colors.grey.shade200,
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
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Cédula: ${it.idNumber}'),
                if (it.createdAt != null)
                  Text('Generado: ${it.createdAt}'),
              ],
            ),
            trailing: Text(
              _fmtCop(it.commissionCop),
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
            ),
          ),
        );
      },
    );
  }
}

class _FooterMatch extends StatelessWidget {
  const _FooterMatch({required this.b});
  final CommissionRequestBreakdown b;

  @override
  Widget build(BuildContext context) {
    if (b.matchesRequest) {
      return const SizedBox.shrink();
    }
    return Card(
      color: Colors.red.shade50,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Row(
          children: const [
            Icon(Icons.info_outline, color: Colors.red),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'La suma de los items NO coincide con el valor solicitado. Revisa los montos.',
                style: TextStyle(color: Colors.red),
              ),
            ),
          ],
        ),
      ),
    );
  }
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
                'No se pudo cargar el desglose.\n$error',
                style: const TextStyle(color: Colors.red),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
