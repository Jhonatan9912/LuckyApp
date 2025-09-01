import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:base_app/presentation/providers/subscription_provider.dart';

/// Ajusta estos valores a tu app real
const String _kPackageName = 'com.tu.paquete';
const String _kProductId = 'cm_suscripcion';

/// Hoja inferior con el estado actual de la suscripción.
class SubscriptionSheet extends StatefulWidget {
  const SubscriptionSheet({super.key});

  @override
  State<SubscriptionSheet> createState() => _SubscriptionSheetState();
}

class _SubscriptionSheetState extends State<SubscriptionSheet> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final subs = context.watch<SubscriptionProvider>();

    final String plan = subs.isPremium ? 'PRO' : 'FREE';
    final String status = subs.isPremium ? 'Activo' : 'Inactivo';

    // ← usa los datos reales del provider
    final DateTime? since = subs.since;
    final DateTime? renewsAt = subs.renewsAt;     // solo si auto-renueva
    final DateTime? expiresAt = subs.expiresAt;   // fecha de expiración real

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                const Icon(Icons.workspace_premium, size: 22),
                const SizedBox(width: 8),
                const Text(
                  'Tu suscripción',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
                const Spacer(),
                _StatusChip(text: status),
              ],
            ),
            const SizedBox(height: 12),

            // Plan & fechas
            _TwoLineRow(label: 'Plan', value: plan),
            if (since != null) _TwoLineRow(label: 'Desde', value: _fmtDate(since)),
            if (expiresAt != null) _TwoLineRow(label: 'Vence', value: _fmtDate(expiresAt)),
            if (renewsAt != null) _TwoLineRow(label: 'Renovación', value: _fmtDate(renewsAt)),

            const SizedBox(height: 8),
            const Divider(height: 24),

            // Beneficios
            const Text(
              'Beneficios incluidos',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            const _Bullet(text: 'Reservar números y funciones avanzadas'),
            const _Bullet(text: 'Jugar con más cifras'),
            const _Bullet(text: 'Notificaciones de premio en tiempo real'),

            const SizedBox(height: 16),

            // Acciones
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _busy ? null : _openManageSubscriptions,
                    icon: const Icon(Icons.manage_accounts),
                    label: const Text('Gestionar'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextButton.icon(
                    onPressed: _busy
                        ? null
                        : () async {
                            setState(() => _busy = true);
                            try {
                              final p = context.read<SubscriptionProvider>();
                              await p.restore();            // pide a Play sus compras
                              await p.refresh(force: true); // refresca estado desde tu backend
                            } finally {
                              if (mounted) setState(() => _busy = false);
                            }
                          },
                    icon: _busy
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.restore),
                    label: const Text('Restaurar compras'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static String _fmtDate(DateTime d) {
    final dd = d.day.toString().padLeft(2, '0');
    final mm = d.month.toString().padLeft(2, '0');
    final yyyy = d.year.toString();
    return '$dd/$mm/$yyyy';
  }

  Future<void> _openManageSubscriptions() async {
    // Deep link a la pantalla de suscripciones de Google Play para tu SKU
    final uri = Uri.parse(
      'https://play.google.com/store/account/subscriptions'
      '?sku=$_kProductId&package=$_kPackageName',
    );

    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      // Fallback: página general de suscripciones
      final fallback = Uri.parse('https://play.google.com/store/account/subscriptions');
      await launchUrl(fallback, mode: LaunchMode.externalApplication);
    }
  }
}

class _TwoLineRow extends StatelessWidget {
  final String label;
  final String value;
  const _TwoLineRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final labelStyle = Theme.of(context).textTheme.bodySmall?.copyWith(
          color: Theme.of(context).colorScheme.outline,
        );
    final valueStyle = Theme.of(context)
        .textTheme
        .bodyLarge
        ?.copyWith(fontWeight: FontWeight.w700);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Text(label, style: labelStyle),
          const Spacer(),
          Text(value, style: valueStyle),
        ],
      ),
    );
  }
}

class _Bullet extends StatelessWidget {
  final String text;
  const _Bullet({required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          const Icon(Icons.check_circle_outline, size: 18),
          const SizedBox(width: 8),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String text;
  const _StatusChip({required this.text});

  @override
  Widget build(BuildContext context) {
    final ok = text.toLowerCase().contains('activo');
    final bg = ok ? Colors.green.shade50 : Colors.red.shade50;
    final fg = ok ? Colors.green.shade800 : Colors.red.shade800;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: fg.withValues(alpha: 0.25)),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: fg,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.2,
        ),
      ),
    );
  }
}
