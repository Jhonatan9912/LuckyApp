import 'package:flutter/material.dart';

String formatWinning(dynamic raw, int digits) {
  if (raw == null) return '';
  var s = raw.toString().trim();
  if (s.isEmpty) return '';

  // Si ya viene con guion, no tocar
  if (s.contains('-')) return s;

  // Solo números
  s = s.replaceAll(RegExp(r'[^0-9]'), '');
  if (s.isEmpty) return '';

  // pad con ceros a la izquierda según digits
  s = s.padLeft(digits, '0');

  // Quinta: 9997-2
  if (digits == 5 && s.length >= 5) {
    return '${s.substring(0, 4)}-${s.substring(4, 5)}';
  }

  return s;
}

class NotificationItem extends StatelessWidget {
  const NotificationItem({super.key, required this.data, required this.onOpen});

  final Map<String, dynamic> data;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final kind = (data['kind'] ?? '').toString();
    final title = (data['title'] ?? '').toString();
    final body = (data['body'] ?? '').toString();
    final read = data['read'] == true;

    // 👇 Nuevo: número ganador formateado (si viene)
final payload = (data['payload'] ?? const {}) as Map<String, dynamic>;
final int digits =
    (payload['digits'] ?? data['digits'] ?? 3) is int
        ? (payload['digits'] ?? data['digits'] ?? 3) as int
        : int.tryParse((payload['digits'] ?? data['digits'] ?? '3').toString()) ?? 3;

final dynamic winningRaw =
    data['winning_formatted'] ??
    data['winning_raw'] ??
    payload['winning_number'] ??
    data['winning_number'];

final String winningFormatted = formatWinning(winningRaw, digits);


    // 👇 Consideramos estos tipos como "notificación de resultado"
    final bool isWinnerKind =
        kind == 'winner_announced' ||
        kind == 'winner_congrats' ||
        kind == 'you_won' ||
        kind == 'result';

    String shorten(String text, {int max = 120}) {
      final t = text.trim();
      if (t.length <= max) return t;
      return '${t.substring(0, max)}… Ver más';
    }
    IconData iconFor(String k) {
      switch (k) {
        case 'withdrawal_rejected':
          return Icons.block;
        case 'withdrawal_approved':
          return Icons.payments_outlined;
        case 'schedule':
          return Icons.event;
        case 'result':
        case 'winner_announced':
        case 'winner_congrats':
        case 'you_won':
          return Icons.emoji_events_outlined;
        default:
          return Icons.notifications_none;
      }
    }

    Color tintFor(BuildContext ctx, String k) {
      switch (k) {
        case 'withdrawal_rejected':
          return Colors.red.shade700;
        case 'withdrawal_approved':
          return Colors.green.shade700;
        case 'schedule':
          return Colors.amber.shade800;
        case 'result':
        case 'winner_announced':
        case 'winner_congrats':
        case 'you_won':
          return Colors.deepPurple.shade700;
        default:
          return Theme.of(ctx).colorScheme.primary;
      }
    }

    final tint = tintFor(context, kind);

    // 👇 Si es notificación de ganador y tenemos número formateado,
    // usamos un subtítulo especial. Si no, mantenemos el resumen normal.
    late final String summary;
    if (isWinnerKind && winningFormatted.isNotEmpty) {

      summary = 'El número ganador es $winningFormatted';
    } else {
      final isLong = body.trim().length > 120;
      summary = isLong ? shorten(body) : body;
    }

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: tint.withValues(alpha: 0.08),
        child: Icon(iconFor(kind), color: tint),
      ),
      title: Text(
        title,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        summary,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        softWrap: true,
      ),
      trailing: Icon(
        read ? Icons.mark_email_read_outlined : Icons.mark_email_unread_outlined,
        color: read ? Colors.black45 : tint,
      ),
      onTap: onOpen,
    );
  }
}
