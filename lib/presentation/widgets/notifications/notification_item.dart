import 'package:flutter/material.dart';

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
        default:
          return Theme.of(ctx).colorScheme.primary;
      }
    }

    final tint = tintFor(context, kind);
    final isLong = body.trim().length > 120;
    final summary = isLong ? shorten(body) : body;

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: tint.withValues(alpha: 0.08),
        child: Icon(iconFor(kind), color: tint),
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
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
