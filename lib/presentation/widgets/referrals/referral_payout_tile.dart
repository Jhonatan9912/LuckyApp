import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:flutter/services.dart';

import 'package:base_app/presentation/providers/referral_provider.dart';
import 'package:base_app/presentation/widgets/payout_request_sheet.dart';

class ReferralPayoutTile extends StatelessWidget {
  final VoidCallback? onWithdraw;
  final String? code;
  final double minToWithdraw;

  const ReferralPayoutTile({
    super.key,
    this.onWithdraw,
    this.code,
    this.minToWithdraw = 100000,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.watch<ReferralProvider>();
    final isLoading = p.loading;

    final currency = (p.payoutCurrency).toUpperCase();
    final symbol = currency == 'COP' ? r'$' : '';
    final fmt = NumberFormat.currency(
      locale: 'es_CO',
      symbol: symbol,
      decimalDigits: 0,
    );

    final available = p.availableCop;
    final held = p.heldCop;
    final inWithdrawal = p.inWithdrawalCop;

    final surface = Theme.of(context).colorScheme.surface;
    final border = Colors.black12;
    final muted = Colors.black54;
    final primary = Theme.of(context).colorScheme.primary;

    final canWithdraw = available >= minToWithdraw;
    final c = code?.trim();

    // ---------- SUBTITLE compacto ----------
    final subtitle = Wrap(
      spacing: 12,
      runSpacing: 2,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        _stat(context, 'Disponible', fmt.format(available), primary),
        _dot(),
        _stat(context, 'Retenida', fmt.format(held), primary),
        _dot(),
        _stat(context, 'En retiro', fmt.format(inWithdrawal), primary),
      ],
    );

    Future<void> openSheetAndRefresh() async {
      if (onWithdraw != null) {
        onWithdraw!();
        return;
      }
      // Abrir hoja para solicitar retiro
      await showPayoutRequestSheet(context);
      // Tras cerrar la hoja, refrescar para traer saldos actualizados desde backend
      if (!context.mounted) return;
      await context.read<ReferralProvider>().load(refresh: true);
    }

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
          tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          leading: const Icon(Icons.card_giftcard),
          title: Row(
            children: [
              Expanded(
                child: Text(
                  (c == null || c.isEmpty)
                      ? 'Programa de referidos'
                      : 'Código: $c',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (c != null && c.isNotEmpty)
                IconButton(
                  tooltip: 'Copiar código',
                  icon: const Icon(Icons.copy_rounded, size: 18),
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: c));
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Código copiado')),
                    );
                  },
                ),
            ],
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: subtitle,
          ),
          children: [
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 16),
              child: SizedBox(
                width: double.infinity,
                child: canWithdraw
                    ? FilledButton.icon(
                        onPressed: isLoading ? null : openSheetAndRefresh,
                        icon: isLoading
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.payments),
                        label: Text(
                          isLoading ? 'Procesando...' : 'Solicitar retiro',
                        ),
                      )
                    : Text(
                        'Mínimo para retirar: ${fmt.format(minToWithdraw)}',
                        style: TextStyle(color: muted, fontSize: 12),
                        textAlign: TextAlign.left,
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Punto separador sutil
  Widget _dot() => const Text('•', style: TextStyle(color: Colors.black38));

  // Label tenue + monto con semibold y color del tema
  Widget _stat(
    BuildContext context,
    String label,
    String value,
    Color amountColor,
  ) {
    return RichText(
      text: TextSpan(
        style: DefaultTextStyle.of(context).style.copyWith(height: 1.2),
        children: [
          TextSpan(
            text: '$label: ',
            style: const TextStyle(
              color: Colors.black54,
              fontWeight: FontWeight.w500,
            ),
          ),
          TextSpan(
            text: value,
            style: TextStyle(
              color: amountColor,
              fontWeight: FontWeight.w600,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}
