import 'package:flutter/material.dart';

class ReferralKpis extends StatelessWidget {
  final int total;
  final int activos;
  final int? inactivos; // opcional

  const ReferralKpis({
    super.key,
    required this.total,
    required this.activos,
    this.inactivos,
  });

  @override
  Widget build(BuildContext context) {
    final int inact = inactivos ?? (total - activos).clamp(0, total).toInt();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Row(
        children: [
          _box('Referidos', '$total'),
          const SizedBox(width: 12),
          _box('Activos', '$activos'),
          const SizedBox(width: 12),
          _box('Inactivos', '$inact'),
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
