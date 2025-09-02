import 'package:flutter/material.dart';

class ReferralKpis extends StatelessWidget {
  final int total;
  final int activos;
  final int? inactivos;
  final double? comisionPendiente;
  final double? comisionPagada;
  final String? moneda;

  const ReferralKpis({
    super.key,
    required this.total,
    required this.activos,
    this.inactivos,
    this.comisionPendiente,
    this.comisionPagada,
    this.moneda,
  });

  @override
  Widget build(BuildContext context) {
    final int inact = inactivos ?? (total - activos).clamp(0, total).toInt();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Column(
        children: [
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
          if (comisionPendiente != null || comisionPagada != null)
            Row(
              children: [
                _box('Pendiente', '${comisionPendiente?.toStringAsFixed(0)} ${moneda ?? ''}'),
                const SizedBox(width: 12),
                _box('Pagado', '${comisionPagada?.toStringAsFixed(0)} ${moneda ?? ''}'),
              ],
            ),
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
