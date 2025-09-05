import 'package:flutter/material.dart';

class ReferralKpis extends StatelessWidget {
  final int total;
  final int activos;
  final int? inactivos;

  // Montos
  final double? disponible;
  final double? retenida;
  final double? enRetiro;
  final double? pagada;
  final String? moneda;

  const ReferralKpis({
    super.key,
    required this.total,
    required this.activos,
    this.inactivos,
    this.disponible,
    this.retenida,
    this.enRetiro,
    this.pagada,
    this.moneda,
  });

  @override
  Widget build(BuildContext context) {
    final int inact = inactivos ?? (total - activos).clamp(0, total).toInt();
    final String cur = moneda ?? '';

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Column(
        children: [
          // KPIs de referidos
          Row(
            children: [
              _box('Referidos', '$total'),
              const SizedBox(width: 12),
              _box('Activos', '$activos'),
              const SizedBox(width: 12),
              _box('Inactivos', '$inact'),
            ],
          ),
          const SizedBox(height: 12),

          // KPIs de comisiones
          if (disponible != null ||
              retenida != null ||
              enRetiro != null ||
              pagada != null)
            Row(
              children: [
                _box('Disponible', '${disponible?.toStringAsFixed(0) ?? '0'} $cur'),
                const SizedBox(width: 12),
                _box('Retenida', '${retenida?.toStringAsFixed(0) ?? '0'} $cur'),
              ],
            ),
          if (enRetiro != null || pagada != null) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                _box('En retiro', '${enRetiro?.toStringAsFixed(0) ?? '0'} $cur'),
                const SizedBox(width: 12),
                _box('Pagada', '${pagada?.toStringAsFixed(0) ?? '0'} $cur'),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _box(String title, String value) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFDEE2E6)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontSize: 12, color: Colors.black54)),
            const SizedBox(height: 4),
            Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }
}
