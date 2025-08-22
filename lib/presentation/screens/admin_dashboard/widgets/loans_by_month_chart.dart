import 'package:flutter/material.dart';

class LoansByMonthChart extends StatelessWidget {
  final List<Map<String, dynamic>> data;
  const LoansByMonthChart({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (data.isEmpty) return const SizedBox.shrink();

    final maxY = data.map((e) => (e['cnt'] ?? 0) as num)
        .fold<num>(0, (a, b) => a > b ? a : b).toDouble();

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Préstamos por Mes', style: theme.textTheme.titleMedium),
          const SizedBox(height: 12),
          SizedBox(
            height: 160,
            child: LayoutBuilder(
              builder: (context, cts) {
                final barW = (cts.maxWidth / (data.length * 1.6)).clamp(6, 28);
                final barColor = theme.colorScheme.primary.withValues(alpha: 0.85); // 👈 aquí

                return Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    for (final item in data)
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Container(
                              height: maxY > 0 ? ((item['cnt'] ?? 0) / maxY) * 120 : 0,
                              width: barW.toDouble(),
                              decoration: BoxDecoration(
                                color: barColor,
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(_label(item['month']), style: theme.textTheme.labelSmall),
                          ],
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ]),
      ),
    );
  }

  String _label(dynamic m) {
    final s = (m ?? '').toString();
    return s.length >= 7 ? s.substring(5, 7) : s;
  }
}
