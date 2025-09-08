import 'package:flutter/material.dart';
import 'notification_item.dart';
import 'notification_detail_sheet.dart';

class NotificationsBottomSheet extends StatelessWidget {
  const NotificationsBottomSheet({
    super.key,
    required this.items,
    this.onRefresh, // opcional: permite pull-to-refresh
  });

  final List<dynamic> items;
  final Future<void> Function()? onRefresh;

  @override
  Widget build(BuildContext context) {
    final sheetHeight = MediaQuery.of(context).size.height * 0.75;
    final bottomSafe = MediaQuery.of(context).padding.bottom + 8;

    Widget buildEmpty() {
      return ListView(
        // Para que el RefreshIndicator funcione con lista vacía
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(16, 24, 16, bottomSafe),
        children: const [
          SizedBox(height: 16),
          Center(
            child: Icon(Icons.notifications_none, size: 48, color: Colors.black38),
          ),
          SizedBox(height: 12),
          Center(
            child: Text(
              'No tienes notificaciones',
              style: TextStyle(color: Colors.black54, fontSize: 16, fontWeight: FontWeight.w600),
            ),
          ),
          SizedBox(height: 6),
          Center(
            child: Text(
              'Cuando haya novedades, aparecerán aquí.',
              style: TextStyle(color: Colors.black45),
              textAlign: TextAlign.center,
            ),
          ),
          SizedBox(height: 8),
        ],
      );
    }

    Widget buildList() {
      return ListView.separated(
        padding: EdgeInsets.fromLTRB(16, 16, 16, bottomSafe),
        itemCount: items.length,
        separatorBuilder: (_, __) => const Divider(height: 16),
        itemBuilder: (_, i) {
          final n = items[i] as Map<String, dynamic>;
          return NotificationItem(
            data: n,
            onOpen: () async {
              await showModalBottomSheet(
                context: context,
                isScrollControlled: true,
                showDragHandle: true,
                shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                ),
                builder: (_) => NotificationDetailSheet(data: n),
              );
            },
          );
        },
      );
    }

    final content = items.isEmpty ? buildEmpty() : buildList();

    return SizedBox(
      height: sheetHeight,
      child: SafeArea(
        top: false,
        child: onRefresh == null
            ? content
            : RefreshIndicator(
                onRefresh: onRefresh!,
                edgeOffset: 8,
                child: content,
              ),
      ),
    );
  }
}
