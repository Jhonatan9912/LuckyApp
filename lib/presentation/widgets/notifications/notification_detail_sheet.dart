import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:base_app/core/config/env.dart';
import 'package:base_app/data/session/session_manager.dart';

class NotificationDetailSheet extends StatelessWidget {
  const NotificationDetailSheet({super.key, required this.data});
  final Map<String, dynamic> data;

  // --- helper: arma URL absoluta si viene relativa ---
  String _absUrl(String rel) {
    if (rel.startsWith('http')) return rel;
    return '${Env.apiBaseUrl}$rel';
  }

  // --- helper: formatea COP ---
  String _fmtCop(String raw) {
    final v = double.tryParse(raw) ?? 0;
    final s = v.toStringAsFixed(0);
    final re = RegExp(r'\B(?=(\d{3})+(?!\d))');
    return '\$${s.replaceAllMapped(re, (m) => '.')}';
  }

  IconData _iconFor(String k) {
    switch (k) {
      case 'withdrawal_rejected':
        return Icons.block;
      case 'withdrawal_approved':
      case 'withdrawal_paid':
        return Icons.payments_outlined;
      case 'schedule':
        return Icons.event;
      case 'result':
        return Icons.emoji_events_outlined;
      default:
        return Icons.notifications_none;
    }
  }

  Color _tintFor(BuildContext ctx, String k) {
    switch (k) {
      case 'withdrawal_rejected':
        return Colors.red.shade700;
      case 'withdrawal_approved':
      case 'withdrawal_paid':
        return Colors.green.shade700;
      case 'schedule':
        return Colors.amber.shade800;
      default:
        return Theme.of(ctx).colorScheme.primary;
    }
  }

  Widget _kv(String k, String v) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Row(
      children: [
        SizedBox(
          width: 130,
          child: Text(k, style: const TextStyle(fontWeight: FontWeight.w600)),
        ),
        Expanded(child: Text(v, textAlign: TextAlign.right)),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final kind = (data['kind'] ?? '').toString();
    final title = (data['title'] ?? '').toString();
    final body = (data['body'] ?? '').toString();
    final payload = (data['payload'] ?? {}) as Map<String, dynamic>;

    final reason = (payload['reason'] ?? payload['rejected_reason'] ?? '')
        .toString();
    final amount = (payload['amount_cop'] ?? payload['amount'] ?? 0).toString();
    final date = (payload['rejected_at'] ?? data['created_at'] ?? '')
        .toString();
    final payoutId = (payload['payout_request_id'] ?? '').toString();

    // datos de pago exitoso
    final accountMasked = (payload['account_masked'] ?? '').toString();
    final note = (payload['note'] ?? '').toString();
    final files =
        (payload['files'] as List?)?.cast<Map<String, dynamic>>() ?? const [];

    final tint = _tintFor(context, kind);
    final icon = _iconFor(kind);

    return SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final maxH = MediaQuery.of(context).size.height * 0.9;
          return ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxH),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        backgroundColor: tint.withValues(alpha: 0.08),
                        child: Icon(icon, color: tint),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          title.isNotEmpty ? title : 'Detalle de notificación',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // ======== PAGO EXITOSO ========
                  if (kind == 'withdrawal_paid' ||
                      kind == 'withdrawal_approved') ...[
                    if (payoutId.isNotEmpty)
                      _kv('Lote de retiro', '#$payoutId'),
                    _kv('Monto', _fmtCop(amount)),
                    if (accountMasked.isNotEmpty) _kv('Cuenta', accountMasked),
                    if (note.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Observación',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.green.shade50,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.green.shade100),
                        ),
                        child: SelectableText(
                          note,
                          style: TextStyle(color: Colors.green.shade800),
                        ),
                      ),
                    ],
                    if (files.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Text(
                        'Evidencias',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: files.map((f) {
                          final url = _absUrl((f['url'] ?? '').toString());
                          final name = (f['name'] ?? '').toString();
                          return GestureDetector(
                            onTap: () {
                              showDialog(
                                context: context,
                                builder: (_) => Dialog(
                                  child: _AuthImage(
                                    url: url,
                                    width: 360,
                                    height: 480,
                                  ),
                                ),
                              );
                            },
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                _AuthImage(url: url), // 👈 carga con JWT
                                const SizedBox(height: 4),
                                SizedBox(
                                  width: 96,
                                  child: Text(
                                    name.isNotEmpty ? name : 'archivo',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: Colors.black54,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                      ),
                    ],
                  ]
                  // ======== RECHAZADO ========
                  else if (kind == 'withdrawal_rejected') ...[
                    _kv('Lote de retiro', '#$payoutId'),
                    _kv('Fecha', date.isEmpty ? '—' : date),
                    _kv('Monto', _fmtCop(amount)),
                    const SizedBox(height: 8),
                    Text(
                      'Motivo del rechazo',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.red.shade100),
                      ),
                      child: SelectableText(
                        reason.isNotEmpty ? reason : body,
                        style: TextStyle(color: Colors.red.shade800),
                      ),
                    ),
                  ]
                  // ======== GENÉRICO ========
                  else ...[
                    Text(body.isNotEmpty ? body : 'Sin contenido'),
                  ],

                  const SizedBox(height: 8),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _AuthImage extends StatefulWidget {
  final String url;
  final double width;
  final double height;

  const _AuthImage({required this.url, this.width = 96, this.height = 96});

  @override
  State<_AuthImage> createState() => _AuthImageState();
}

class _AuthImageState extends State<_AuthImage> {
  Uint8List? _bytes;
  bool _error = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final token = await SessionManager().getToken();
      debugPrint('[AuthImage] GET ${widget.url} with token=${token != null}');
      final res = await http.get(
        Uri.parse(widget.url),
        headers: token != null ? {'Authorization': 'Bearer $token'} : {},
      );
      debugPrint(
        '[AuthImage] status=${res.statusCode}, bytes=${res.bodyBytes.length}',
      );

      if (res.statusCode >= 200 && res.statusCode < 300) {
        setState(() => _bytes = res.bodyBytes);
      } else {
        setState(() => _error = true);
      }
    } catch (_) {
      setState(() => _error = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error) {
      return Container(
        width: widget.width,
        height: widget.height,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.black12,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Icon(Icons.broken_image_outlined),
      );
    }
    if (_bytes == null) {
      return Container(
        width: widget.width,
        height: widget.height,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.black12,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const CircularProgressIndicator(strokeWidth: 2),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Image.memory(
        _bytes!,
        width: widget.width,
        height: widget.height,
        fit: BoxFit.cover,
      ),
    );
  }
}
