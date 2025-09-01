import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:base_app/presentation/providers/referral_provider.dart';

class ReferralPayoutTile extends StatelessWidget {
  final double pending;              // fallback (ya no se usará si hay provider)
  final VoidCallback onWithdraw;
  final String? code;
  final double minToWithdraw;

  const ReferralPayoutTile({
    super.key,
    required this.pending,
    required this.onWithdraw,
    this.code,
    this.minToWithdraw = 1,
  });

  @override
  Widget build(BuildContext context) {
    // ✅ NO nullable: necesitamos el provider real
    final p = context.watch<ReferralProvider>();
    final currency = p.payoutCurrency.toUpperCase();
    final amount   = p.payoutPending;

    final symbol = currency == 'COP' ? r'$' : '';
    final fmt = NumberFormat.currency(
      locale: 'es_CO',
      symbol: symbol,
      decimalDigits: 0,
    );

    final surface = Theme.of(context).colorScheme.surface;
    final border  = Colors.black12;

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
            'Comisión disponible: ${fmt.format(amount)}',
            style: const TextStyle(color: Colors.black87),
          ),
          children: [
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
              child: Row(
                children: [
                  _kpi(context, 'Disponible', amount, currency),
                ],
              ),
            ),
            if (amount >= minToWithdraw)
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

  Widget _kpi(BuildContext context, String label, double value, String currency) {
    final symbol = currency.toUpperCase() == 'COP' ? r'$' : '';
    final fmt = NumberFormat.currency(
      locale: 'es_CO',
      symbol: symbol,
      decimalDigits: 0,
    );

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
            Text(
              fmt.format(value),
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }
}
