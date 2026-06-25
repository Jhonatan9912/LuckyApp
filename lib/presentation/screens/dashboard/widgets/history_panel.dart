import 'package:flutter/material.dart';
import 'package:base_app/core/utils/lottery_number_format.dart';

class HistoryPanel extends StatelessWidget {
  /// items: { game_id|id, numbers: [int|str], winning_number?, result|status?,
  ///          lottery_name|lottery?, played_date|date?|played_at?, played_time|time? }
  final List<Map<String, dynamic>> items;
  final VoidCallback? onRefresh;

  const HistoryPanel({super.key, required this.items, this.onRefresh});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.95),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFEAD88A), width: 1),
          boxShadow: const [
            BoxShadow(
              color: Color(0x18D4AF37),
              blurRadius: 8,
              offset: Offset(0, 3),
            ),
          ],
        ),
        child: items.isEmpty
            ? _EmptyState(onRefresh: onRefresh)
            : ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: items.length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (context, i) {
                  final it = items[i];

                  final gameId =
                      (it['game_id'] as num?)?.toInt() ??
                          (it['id'] as num?)?.toInt() ??
                          0;

                  final rawNums = (it['numbers'] as List?) ?? const [];
                  final nums = rawNums
                      .map((e) => int.tryParse(e.toString()) ?? 0)
                      .toList();

                  final win = (it['winning_number'] as num?)?.toInt();

                  // ---------- Cálculo ROBUSTO de dígitos ----------
                  int digits = (it['digits'] as num?)?.toInt() ??
                      (it['numbers_digits'] as num?)?.toInt() ??
                      0;

                  if (digits <= 0) {
                    int inferred = 0;

                    for (final e in rawNums) {
                      final len = e.toString().length;
                      if (len > inferred) inferred = len;
                    }

                    if (win != null) {
                      final lenWin = win.toString().length;
                      if (lenWin > inferred) inferred = lenWin;
                    }

                    // 👇 aquí ya puedes decidir si permitir quinta:
                    // - si el backend manda 5 cifras, inferred=5 y lo respetamos
                    // normalizamos (mínimo 3, máximo 6)
                    if (inferred < 2) inferred = 2;
                    if (inferred > 6) inferred = 6;

                    digits = inferred;
                  }

                  final resStr = (it['result'] ?? it['status'] ?? '')
                      .toString()
                      .toLowerCase();

                  final lottery =
                      (it['lottery_name'] ?? it['lottery'] ?? '')
                          .toString()
                          .trim();

                  final dateText =
                      (it['scheduled_date'] ??
                              it['played_date'] ??
                              it['date'] ??
                              '')
                          .toString()
                          .trim();

                  final timeText =
                      (it['scheduled_time'] ??
                              it['played_time'] ??
                              it['time'] ??
                              '')
                          .toString()
                          .trim();

                  final outcome = _computeOutcome(
                    resStr: resStr,
                    win: win,
                    nums: nums,
                  );

                  return _HistoryCard(
                    gameId: gameId,
                    numbers: nums,
                    winningNumber: win,
                    outcome: outcome,
                    lottery: lottery,
                    dateText: dateText,
                    timeText: timeText,
                    digits: digits,
                  );
                },
              ),
      ),
    );
  }

  _Outcome _computeOutcome({
    required String resStr,
    required int? win,
    required List<int> nums,
  }) {
    final isPlayingByText =
        resStr.contains('play') ||
            resStr.contains('en juego') ||
            resStr.contains('jugando') ||
            resStr.contains('scheduled') ||
            resStr.contains('program');

    if (win == null && (isPlayingByText || resStr.isEmpty)) {
      return _Outcome.inPlay;
    }
    if (win == null) return _Outcome.inPlay;

    return nums.contains(win) ? _Outcome.won : _Outcome.lost;
  }
}

enum _Outcome { inPlay, won, lost }

class _HistoryCard extends StatelessWidget {
  final int gameId;
  final List<int> numbers;
  final int? winningNumber;
  final _Outcome outcome;
  final String lottery;
  final String dateText;
  final String timeText;
  final int digits; // 3,4,5

  const _HistoryCard({
    required this.gameId,
    required this.numbers,
    required this.winningNumber,
    required this.outcome,
    required this.lottery,
    required this.dateText,
    required this.timeText,
    required this.digits,
  });

  @override
  Widget build(BuildContext context) {
    final borderColor = switch (outcome) {
      _Outcome.won => Colors.green.withValues(alpha: 0.25),
      _Outcome.lost => Colors.red.withValues(alpha: 0.25),
      _Outcome.inPlay => Colors.blueGrey.withValues(alpha: 0.25),
    };

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Juego #$gameId',
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                ),
              ),
              const SizedBox(width: 8),
              _StatusChip(outcome: outcome),
            ],
          ),
          const SizedBox(height: 6),

          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: numbers.map((n) => _ball(n)).toList(),
          ),

          const SizedBox(height: 10),

          if (winningNumber != null)
            Row(
              children: [
                const Text(
                  'Número ganador: ',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                Text(
                  formatGameNumber(winningNumber!, digits),
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: outcome == _Outcome.won
                        ? Colors.green
                        : (outcome == _Outcome.lost
                            ? Colors.red
                            : Colors.blueGrey),
                  ),
                ),
              ],
            ),

          if (lottery.isNotEmpty || dateText.isNotEmpty || timeText.isNotEmpty)
            ...[
              const SizedBox(height: 10),
              const Divider(height: 1),
              const SizedBox(height: 10),
              if (lottery.isNotEmpty) _InfoRow(label: 'Lotería', value: lottery),
              if (dateText.isNotEmpty) _InfoRow(label: 'Fecha', value: dateText),
              if (timeText.isNotEmpty) _InfoRow(label: 'Hora', value: timeText),
            ],
        ],
      ),
    );
  }

  Widget _ball(int n) {
    final txt = formatGameNumber(n, digits);
    final isWin = (winningNumber != null && n == winningNumber);

    final double w = digits <= 2 ? 40 : (digits == 3 ? 44 : (digits == 4 ? 52 : 60));

    Color fill;
    Color stroke;
    Color? textColor;

    switch (outcome) {
      case _Outcome.won:
        fill = isWin
            ? Colors.green.withValues(alpha: 0.12)
            : Colors.orange.withValues(alpha: 0.12);
        stroke = isWin ? Colors.green : Colors.orange;
        textColor = isWin ? Colors.green[800] : Colors.orange[900];
        break;
      case _Outcome.lost:
        fill = Colors.orange.withValues(alpha: 0.12);
        stroke = Colors.orange;
        textColor = Colors.orange[900];
        break;
      case _Outcome.inPlay:
        fill = Colors.blueGrey.withValues(alpha: 0.10);
        stroke = Colors.blueGrey;
        textColor = Colors.blueGrey[800];
        break;
    }

    return Container(
      width: w,
      height: w,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: fill,
        border: Border.all(color: stroke, width: 1.4),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            txt,
            style: TextStyle(fontWeight: FontWeight.w700, color: textColor),
          ),
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final _Outcome outcome;
  const _StatusChip({required this.outcome});

  @override
  Widget build(BuildContext context) {
    final (bg, fg, label, border) = switch (outcome) {
      _Outcome.won => (
          Colors.green.withValues(alpha: 0.15),
          Colors.green[800],
          'Ganado',
          Colors.green.withValues(alpha: 0.4),
        ),
      _Outcome.lost => (
          Colors.red.withValues(alpha: 0.15),
          Colors.red[800],
          'Perdido',
          Colors.red.withValues(alpha: 0.4),
        ),
      _Outcome.inPlay => (
          Colors.blueGrey.withValues(alpha: 0.15),
          Colors.blueGrey[900],
          'En juego',
          Colors.blueGrey.withValues(alpha: 0.4),
        ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: border),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: fg),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 70,
            child: Text(
              '$label:',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(child: Text(value, overflow: TextOverflow.ellipsis)),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final VoidCallback? onRefresh;
  const _EmptyState({this.onRefresh});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.history,
              size: 40,
              color: Colors.black.withValues(alpha: 0.35),
            ),
            const SizedBox(height: 12),
            const Text(
              'Aún no tienes juegos en el historial.',
              style: TextStyle(fontSize: 14, color: Colors.black54),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            if (onRefresh != null)
              OutlinedButton.icon(
                onPressed: onRefresh,
                icon: const Icon(Icons.refresh),
                label: const Text('Actualizar'),
              ),
          ],
        ),
      ),
    );
  }
}
