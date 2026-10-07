// lib/web/player/player_history_page.dart
import 'package:flutter/material.dart';

import 'package:base_app/core/utils/lottery_number_format.dart';

import '../shell/web_shell_layout.dart';
import '../theme/web_palette.dart';
import '../widgets/gold_button.dart';
import '../widgets/web_ui.dart';

enum HistoryOutcome { inPlay, won, lost }

/// Fila de historial ya interpretada (misma lógica que la app).
class HistoryEntry {
  final int gameId;
  final List<int> numbers;
  final int? winning;
  final int digits;
  final String lottery;
  final String date;
  final String time;
  final HistoryOutcome outcome;

  HistoryEntry._(
    this.gameId,
    this.numbers,
    this.winning,
    this.digits,
    this.lottery,
    this.date,
    this.time,
    this.outcome,
  );

  factory HistoryEntry.fromMap(Map<String, dynamic> it) {
    final gameId =
        (it['game_id'] as num?)?.toInt() ?? (it['id'] as num?)?.toInt() ?? 0;
    final rawNums = (it['numbers'] as List?) ?? const [];
    final nums = rawNums.map((e) => int.tryParse(e.toString()) ?? 0).toList();
    final win = (it['winning_number'] as num?)?.toInt();

    int digits =
        (it['digits'] as num?)?.toInt() ??
        (it['numbers_digits'] as num?)?.toInt() ??
        0;
    if (digits <= 0) {
      var inferred = 0;
      for (final e in rawNums) {
        if (e.toString().length > inferred) inferred = e.toString().length;
      }
      if (win != null && win.toString().length > inferred) {
        inferred = win.toString().length;
      }
      digits = inferred.clamp(2, 6);
    }

    // Sin número ganador el juego sigue en curso (igual que en la app).
    final outcome = win == null
        ? HistoryOutcome.inPlay
        : (nums.contains(win) ? HistoryOutcome.won : HistoryOutcome.lost);

    return HistoryEntry._(
      gameId,
      nums,
      win,
      digits,
      (it['lottery_name'] ?? it['lottery'] ?? '').toString().trim(),
      (it['scheduled_date'] ?? it['played_date'] ?? it['date'] ?? '')
          .toString()
          .trim(),
      (it['scheduled_time'] ?? it['played_time'] ?? it['time'] ?? '')
          .toString()
          .trim(),
      outcome,
    );
  }
}

class PlayerHistoryPage extends StatefulWidget {
  final List<Map<String, dynamic>> items;
  final Future<void> Function() onRefresh;
  final bool locked;
  final VoidCallback onOpenPlans;

  const PlayerHistoryPage({
    super.key,
    required this.items,
    required this.onRefresh,
    required this.locked,
    required this.onOpenPlans,
  });

  @override
  State<PlayerHistoryPage> createState() => _PlayerHistoryPageState();
}

class _PlayerHistoryPageState extends State<PlayerHistoryPage> {
  HistoryOutcome? _filter;
  bool _refreshing = false;

  Future<void> _refresh() async {
    setState(() => _refreshing = true);
    try {
      await widget.onRefresh();
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final all = widget.items.map(HistoryEntry.fromMap).toList();
    final rows = _filter == null
        ? all
        : all.where((e) => e.outcome == _filter).toList();
    final won = all.where((e) => e.outcome == HistoryOutcome.won).length;
    final inPlay = all.where((e) => e.outcome == HistoryOutcome.inPlay).length;

    if (widget.locked) {
      return WebPage(
        children: [
          WebPanel(
            child: EmptyState(
              icon: Icons.lock_outline_rounded,
              title: 'Historial disponible con un plan',
              message:
                  'Activa un plan con esta modalidad para ver tus juegos, resultados y premios.',
              action: GoldButton(
                label: 'Ver planes',
                expand: false,
                onPressed: widget.onOpenPlans,
              ),
            ),
          ),
        ],
      );
    }

    return WebPage(
      children: [
        ResponsiveGrid(
          minItemWidth: 200,
          children: [
            StatTile(
              label: 'Juegos jugados',
              value: '${all.length}',
              icon: Icons.casino_outlined,
            ),
            StatTile(
              label: 'En juego',
              value: '$inPlay',
              icon: Icons.hourglass_top_rounded,
              color: WebPalette.amber,
            ),
            StatTile(
              label: 'Ganados',
              value: '$won',
              icon: Icons.emoji_events_outlined,
              color: WebPalette.emerald,
            ),
          ],
        ),
        const SizedBox(height: 22),
        WebPanel(
          title: 'Tus juegos',
          subtitle: 'Resultados y programación de cada sorteo',
          icon: Icons.history_rounded,
          actions: [
            WebIconButton(
              icon: _refreshing
                  ? Icons.hourglass_empty_rounded
                  : Icons.refresh_rounded,
              tooltip: 'Actualizar',
              onPressed: _refreshing ? null : _refresh,
            ),
          ],
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: WebSegmented<HistoryOutcome?>(
                  options: const [
                    (null, 'Todos'),
                    (HistoryOutcome.inPlay, 'En juego'),
                    (HistoryOutcome.won, 'Ganados'),
                    (HistoryOutcome.lost, 'Perdidos'),
                  ],
                  value: _filter,
                  onChanged: (v) => setState(() => _filter = v),
                ),
              ),
              const SizedBox(height: 18),
              if (rows.isEmpty)
                const EmptyState(
                  icon: Icons.inbox_outlined,
                  title: 'Sin juegos para mostrar',
                  message:
                      'Cuando reserves números, aparecerán aquí con su estado.',
                )
              else
                WebTable<HistoryEntry>(
                  rows: rows,
                  mobileTitle: (e) => Text(
                    'Juego #${e.gameId}',
                    style: WebPalette.display(16, weight: FontWeight.w700),
                  ),
                  columns: [
                    WebColumn(
                      'Juego',
                      (e) => CellText('#${e.gameId}', strong: true),
                      flex: 1,
                    ),
                    WebColumn(
                      'Tus números',
                      (e) => NumberPills(
                        [
                          for (final n in e.numbers)
                            formatGameNumber(n, e.digits),
                        ],
                        highlight: e.winning == null
                            ? null
                            : formatGameNumber(e.winning!, e.digits),
                      ),
                      flex: 4,
                    ),
                    WebColumn(
                      'Lotería',
                      (e) => CellText(
                        e.lottery.isEmpty ? 'Por programar' : e.lottery,
                      ),
                      flex: 2,
                    ),
                    WebColumn(
                      'Fecha',
                      (e) => CellText(
                        [e.date, e.time].where((s) => s.isNotEmpty).join(' · '),
                      ),
                      flex: 2,
                    ),
                    WebColumn(
                      'Ganador',
                      (e) => CellText(
                        e.winning == null
                            ? '—'
                            : formatGameNumber(e.winning!, e.digits),
                        mono: true,
                      ),
                      flex: 1,
                    ),
                    WebColumn(
                      'Estado',
                      (e) => _OutcomeChip(e.outcome),
                      flex: 1,
                    ),
                  ],
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _OutcomeChip extends StatelessWidget {
  final HistoryOutcome o;
  const _OutcomeChip(this.o);

  @override
  Widget build(BuildContext context) => switch (o) {
    HistoryOutcome.inPlay => const StatusChip(
      label: 'En juego',
      color: WebPalette.amber,
    ),
    HistoryOutcome.won => const StatusChip(
      label: 'Ganado',
      color: WebPalette.emerald,
      icon: Icons.emoji_events_rounded,
    ),
    HistoryOutcome.lost => const StatusChip(
      label: 'Perdido',
      color: WebPalette.textFaint,
    ),
  };
}
