import 'package:flutter/material.dart';

class ReferralPayoutTile extends StatelessWidget {
  final double pending;                // comisión disponible
  final VoidCallback onWithdraw;       // acción para solicitar retiro
  final String? code;                  // código del usuario (opcional)
  final double minToWithdraw;          // mínimo para mostrar el botón

  const ReferralPayoutTile({
    super.key,
    required this.pending,
    required this.onWithdraw,
    this.code,
    this.minToWithdraw = 1,            // cambia a 20000 si quieres un mínimo real
  });

  @override
  Widget build(BuildContext context) {
    final surface = Theme.of(context).colorScheme.surface;
    final border = Colors.black12;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 6),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(14),
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 8)],
        border: Border.all(color: border),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          leading: const Icon(Icons.card_giftcard),
          title: Text(
            code == null ? 'Programa de referidos' : 'Código: $code',
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          subtitle: Text(
            'Comisión disponible: \$${pending.toStringAsFixed(0)}',
            style: const TextStyle(color: Colors.black87),
          ),
          children: [
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
              child: Row(
                children: [
                  _kpi(context, 'Disponible', pending),
                ],
              ),
            ),
            if (pending >= minToWithdraw)      // 👈 SOLO si hay saldo (o mínimo)
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 16),
                child: FilledButton.icon(
                  onPressed: onWithdraw,
                  icon: const Icon(Icons.payments),
                  label: const Text('Solicitar retiro'),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _kpi(BuildContext context, String label, double value) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.black12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(fontSize: 12, color: Colors.black54)),
            const SizedBox(height: 4),
            Text('\$${value.toStringAsFixed(0)}',
                style: const TextStyle(fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }
}
