import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:base_app/presentation/providers/subscription_provider.dart';
import 'package:base_app/core/ui/dialogs.dart';

/// Hoja inferior con el estado actual de la suscripción + acción de cancelar.
/// UI sola; la acción real de cancelar la conectamos en el siguiente paso.
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

    // Más adelante conectamos fechas/plan si agregas getters en el provider.
    final String plan = subs.isPremium ? 'PRO' : 'FREE';
    final String status = subs.isPremium ? 'Activo' : 'Inactivo';
    final DateTime? renewsAt = null; // por ahora
    final DateTime? since = null; // por ahora

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
            if (since != null)
              _TwoLineRow(label: 'Desde', value: _fmtDate(since)),
            if (renewsAt != null)
              _TwoLineRow(label: 'Renovación', value: _fmtDate(renewsAt)),

            const SizedBox(height: 8),
            const Divider(height: 24),

            // Beneficios (ejemplo)
            const Text(
              'Beneficios incluidos',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            const _Bullet(text: 'Reservar números y funciones avanzadas'),
            const _Bullet(text: 'Jugar con más cifras'),
            const _Bullet(text: 'Notificaciones de premio en tiempo real'),
            const SizedBox(height: 8),

            // Acciones
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _busy
                        ? null
                        : () => Navigator.of(context).pushNamed('/pro'),
                    icon: const Icon(Icons.info_outline),
                    label: const Text('Gestionar'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: (!_busy && subs.isPremium)
                        ? () => _confirmAndCancel(subs)
                        : null,
                    icon: _busy
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.cancel_schedule_send),
                    label: const Text('Cancelar suscripción'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  static String _fmtDate(DateTime d) {
    // formato compacto DD/MM/YYYY
    final dd = d.day.toString().padLeft(2, '0');
    final mm = d.month.toString().padLeft(2, '0');
    final yyyy = d.year.toString();
    return '$dd/$mm/$yyyy';
  }

  Future<void> _confirmAndCancel(SubscriptionProvider subs) async {
  if (!mounted) return;

  // Confirmación simple
  final confirm = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Cancelar suscripción'),
      content: const Text(
        '¿Seguro que quieres cancelar tu plan PRO?\n'
        'Perderás las funciones premium al finalizar tu periodo actual.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('No'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          child: const Text('Sí, cancelar'),
        ),
      ],
    ),
  );

  if (confirm != true || !mounted) return;

  setState(() => _busy = true);
  try {
    // 👇 Este método lo crearemos ahora en el provider
    final ok = await subs.cancel();

    if (!mounted) return;

    if (ok) {
      await subs.refresh(force: true);
      if (!mounted) return;
      await AppDialogs.success(
        context: context,
        title: 'Hecho',
        message:
            'Tu suscripción fue cancelada. Mantendrás acceso PRO hasta el fin del periodo vigente.',
        okText: 'OK',
      );
      if (mounted) Navigator.of(context).maybePop(); // cierra la hoja
    } else {
      await AppDialogs.error(
        context: context,
        title: 'No se pudo cancelar',
        message: 'Intenta de nuevo en unos minutos.',
      );
    }
  } finally {
    if (mounted) setState(() => _busy = false);
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
    final valueStyle = Theme.of(
      context,
    ).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w700);
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
